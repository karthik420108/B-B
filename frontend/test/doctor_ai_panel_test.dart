import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/core/network/api_client.dart';
import 'package:health_wallet/core/storage/token_storage.dart';
import 'package:health_wallet/features/doctor/doctor_ai_panel.dart';
import 'package:health_wallet/models/models.dart';
import 'package:health_wallet/providers/providers.dart';
import 'package:health_wallet/services/doctor_repository.dart';

/// Fake repository so the panel can be exercised without a backend.
///
/// Every method the panel calls is overridden, so the underlying [ApiClient]
/// is never used to make a request.
class _FakeDoctorRepository extends DoctorRepository {
  _FakeDoctorRepository({
    this.answer,
    this.conversation = const [],
    this.onClear,
  }) : super(ApiClient(TokenStorage()));

  final AiAnswer? answer;
  final List<ConversationMessage> conversation;
  final void Function()? onClear;

  /// Questions the panel sent, in order.
  final List<String> askedQuestions = [];

  /// File ids the panel focused on, per question.
  final List<List<String>?> focusedIds = [];

  @override
  Future<AiAnswer> askDoctorAi(
    String shareIdOrToken,
    String question, {
    int topK = 8,
    List<String>? documentIds,
    bool resetConversation = false,
  }) async {
    askedQuestions.add(question);
    focusedIds.add(documentIds);
    return answer ??
        AiAnswer(
          question: question,
          answer: 'Stub answer',
          grounded: true,
          provider: 'local',
        );
  }

  @override
  Future<List<ConversationMessage>> doctorConversation(String shareIdOrToken) async => conversation;

  @override
  Future<void> clearDoctorConversation(String shareIdOrToken) async {
    onClear?.call();
  }
}

DoctorBundle _bundle({List<DocumentSummary> docs = const []}) => DoctorBundle(
      patientName: 'Ravi Kumar',
      documents: docs,
      observations: const [],
      conditions: const [],
      allergies: const [],
      medications: const [],
      duplicateAlerts: const [],
      medicationAlerts: null,
    );

DocumentSummary _doc(String id, String name) => DocumentSummary(
      id: id,
      originalName: name,
      category: 'laboratory',
      mimeType: 'text/plain',
      size: 1024,
      extractionStatus: 'extracted',
    );

Widget _host(DoctorRepository repo, DoctorBundle bundle) => ProviderScope(
      overrides: [doctorRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          // The real app places the panel inside the bundle ListView. A tall
          // test viewport ensures every child is built without scrolling.
          body: ListView(
            children: [
              DoctorAiPanel(shareIdOrToken: 'a'.padLeft(24, '0'), bundle: bundle),
            ],
          ),
        ),
      ),
    );

/// Makes the test surface tall enough that the whole panel is built eagerly.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('AI panel states which patient is being analyzed', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(_host(_FakeDoctorRepository(), _bundle()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Analyzing records for: Ravi Kumar'), findsOneWidget);
    expect(find.text('Suggested questions'), findsOneWidget);
    expect(find.text('AI Medical History Assistant'), findsOneWidget);
    // Empty state invites the first question.
    expect(find.textContaining('Ask a question about this patient'), findsOneWidget);
  });

  /// Scrolls a chip into view - the panel lives in a lazy [ListView].
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('AI panel lists in-scope files as focus chips', (tester) async {
    final docs = [_doc('d1', 'lab-hba1c-jan.txt'), _doc('d2', 'lab-hba1c-apr.txt')];
    _useTallViewport(tester);
    await tester.pumpWidget(_host(_FakeDoctorRepository(), _bundle(docs: docs)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('lab-hba1c-jan.txt'), findsWidgets);
    expect(find.textContaining('lab-hba1c-apr.txt'), findsWidgets);
  });

  testWidgets('asking a question renders the grounded answer and its sources', (tester) async {
    final answer = AiAnswer(
      question: 'Compare the latest HbA1c result with the previous reports.',
      answer: 'HbA1c: 8.1 % on 2026-01-15; 6.9 % on 2026-07-25. A decrease of 1.20.',
      grounded: true,
      provider: 'local',
      citations: [
        Citation(kind: 'observation', documentId: 'd1', documentName: 'lab-hba1c-jan.txt', label: 'HbA1c'),
        Citation(kind: 'observation', documentId: 'd2', documentName: 'lab-hba1c-apr.txt', label: 'HbA1c'),
      ],
    );
    final repo = _FakeDoctorRepository(answer: answer);

    _useTallViewport(tester);
    await tester.pumpWidget(_host(repo, _bundle(docs: [_doc('d1', 'lab-hba1c-jan.txt')])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await scrollTo(tester, find.text('Compare the latest blood report with previous reports.'));
    await tester.tap(find.text('Compare the latest blood report with previous reports.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('A decrease of 1.20'), findsOneWidget);
    expect(find.textContaining('lab-hba1c-jan.txt'), findsWidgets);
    expect(repo.askedQuestions.single, contains('Compare the latest blood report'));
  });

  testWidgets('an unreadable-file notice is surfaced instead of being hidden', (tester) async {
    final answer = AiAnswer(
      question: 'Summarize this patient\'s medical history.',
      answer: 'Summary based on readable files only.',
      grounded: true,
      provider: 'local',
      coverage: AiCoverage(
        documentsInScope: 2,
        documentsWithText: 1,
        unreadable: [
          UnreadableDocument(
            documentId: 'd2',
            documentName: 'scan.png',
            status: 'failed',
            reason: 'No text could be recovered.',
          ),
        ],
      ),
    );

    _useTallViewport(tester);
    await tester.pumpWidget(_host(_FakeDoctorRepository(answer: answer), _bundle()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await scrollTo(tester, find.text('Summarize this patient\'s medical history.'));
    await tester.tap(find.text('Summarize this patient\'s medical history.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('could not be analyzed'), findsOneWidget);
    expect(find.textContaining('scan.png'), findsNothing); // name not leaked in the banner count
  });

  testWidgets('an insufficient-evidence answer is shown as an info banner', (tester) async {
    final answer = AiAnswer(
      question: 'What was the patient\'s last brain MRI result?',
      answer: 'No relevant records were found in this patient\'s authorized share.',
      grounded: true,
      provider: 'local',
      uncertainty: Uncertainty(level: 'high', missing: true, reason: 'No matching records.'),
    );

    _useTallViewport(tester);
    await tester.pumpWidget(_host(_FakeDoctorRepository(answer: answer), _bundle()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final q = find.textContaining('significant changes', findRichText: true);
    await scrollTo(tester, q);
    await tester.tap(q);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('No relevant records were found'), findsOneWidget);
  });

  testWidgets('clear conversation asks for confirmation and resets the thread', (tester) async {
    var cleared = false;
    final repo = _FakeDoctorRepository(
      conversation: [
        ConversationMessage(role: 'doctor', content: 'What are the HbA1c results?'),
        ConversationMessage(role: 'assistant', content: 'HbA1c 8.1 % on 2026-01-15.'),
      ],
      onClear: () => cleared = true,
    );

    _useTallViewport(tester);
    await tester.pumpWidget(_host(repo, _bundle()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.textContaining('HbA1c 8.1 %'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Clear conversation?'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
    expect(find.textContaining('HbA1c 8.1 %'), findsNothing);
    expect(find.textContaining('Ask a question about this patient'), findsOneWidget);
  });

  testWidgets('a restored conversation is replayed on open', (tester) async {
    final repo = _FakeDoctorRepository(conversation: [
      ConversationMessage(role: 'doctor', content: 'What are the HbA1c results?'),
      ConversationMessage(role: 'assistant', content: 'HbA1c 8.1 % on 2026-01-15.'),
    ]);

    _useTallViewport(tester);
    await tester.pumpWidget(_host(repo, _bundle()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('What are the HbA1c results?'), findsOneWidget);
    expect(find.textContaining('HbA1c 8.1 %'), findsOneWidget);
  });

  testWidgets('tapping a focus chip scopes the next question to that file', (tester) async {
    final repo = _FakeDoctorRepository();
    _useTallViewport(tester);
    await tester.pumpWidget(_host(repo, _bundle(docs: [_doc('d1', 'lab-hba1c-jan.txt')])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.textContaining('lab-hba1c-jan.txt').first);
    await tester.pump();

    expect(find.textContaining('Next question will be limited to 1 selected file'), findsOneWidget);

    await tester.tap(find.text('Summarize this patient\'s medical history.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.askedQuestions, hasLength(1));
    expect(repo.focusedIds.single, ['d1']);
  });
}
