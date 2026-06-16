import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_labeled_switch.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders title + subtitle and the current value', (tester) async {
    await pump(
      tester,
      KubbLabeledSwitch(
        title: 'Anspiel 2-4-6',
        subtitle: 'Standard-Anspielregel',
        value: true,
        onChanged: (_) {},
      ),
    );
    expect(find.text('Anspiel 2-4-6'), findsOneWidget);
    expect(find.text('Standard-Anspielregel'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('toggling reports the new value', (tester) async {
    bool? next;
    await pump(
      tester,
      KubbLabeledSwitch(
        title: 'Diggy',
        value: true,
        onChanged: (v) => next = v,
      ),
    );
    await tester.tap(find.byType(Switch));
    expect(next, isFalse);
  });
}
