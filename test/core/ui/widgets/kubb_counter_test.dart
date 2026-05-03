import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_counter.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the integer value as text', (tester) async {
    await pump(
      tester,
      const KubbCounter(label: 'Treffer', value: 42),
    );

    expect(find.text('TREFFER'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('masked mode replaces value with em-dash', (tester) async {
    await pump(
      tester,
      const KubbCounter(label: 'Treffer', value: 42, masked: true),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('42'), findsNothing);
  });

  testWidgets('hit tone paints big number in KubbTokens.hit', (tester) async {
    await pump(
      tester,
      const KubbCounter(label: 'Treffer', value: 7, tone: KubbCounterTone.hit),
    );

    final number = tester.widget<Text>(find.text('7'));
    expect(number.style?.color, KubbTokens.hit);
  });
}
