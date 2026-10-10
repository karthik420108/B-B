import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/core/network/api_exception.dart';
import 'package:health_wallet/widgets/common_widgets.dart';

void main() {
  testWidgets('ErrorPanel keeps its retry button from overflowing in a narrow wrapper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(120, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Regression: a very narrow parent used to squeeze the button's internal
    // Row down to ~22px and overflow it horizontally (yellow/black stripes).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 30,
              child: ErrorPanel(
                error: ApiException(statusCode: 503, code: 'UNAVAILABLE', message: 'Server busy'),
                onRetry: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'retry button must never RenderFlex-overflow');
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('ErrorPanel renders the retry button at full size in a normal layout', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorPanel(
            error: ApiException(statusCode: 501, code: 'NOT_IMPLEMENTED', message: 'nope'),
            onRetry: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Try again'), findsOneWidget);
  });
}