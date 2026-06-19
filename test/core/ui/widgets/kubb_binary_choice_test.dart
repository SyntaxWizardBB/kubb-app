import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_binary_choice.dart';

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

  const options = <KubbChoiceOption<String>>[
    KubbChoiceOption(value: 'ekc', title: 'EKC', subtitle: '1 Pkt/Kubb + 3/Satz'),
    KubbChoiceOption(value: 'classic', title: 'Klassisch', subtitle: 'Klassisches System'),
  ];

  testWidgets('renders a card per option with title + subtitle', (tester) async {
    await pump(
      tester,
      KubbBinaryChoice<String>(
        options: options,
        selected: 'ekc',
        onChanged: (_) {},
      ),
    );
    expect(find.text('EKC'), findsOneWidget);
    expect(find.text('Klassisch'), findsOneWidget);
    expect(find.text('1 Pkt/Kubb + 3/Satz'), findsOneWidget);
  });

  testWidgets('tapping an option reports its value', (tester) async {
    String? picked;
    await pump(
      tester,
      KubbBinaryChoice<String>(
        options: options,
        selected: 'ekc',
        onChanged: (v) => picked = v,
      ),
    );
    await tester.tap(find.text('Klassisch'));
    expect(picked, 'classic');
  });

  testWidgets('selected option shows the checked radio icon, others unchecked',
      (tester) async {
    await pump(
      tester,
      KubbBinaryChoice<String>(
        options: options,
        selected: 'classic',
        onChanged: (_) {},
      ),
    );
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  testWidgets('supports a three-way choice (KO type) generically',
      (tester) async {
    String? picked;
    await pump(
      tester,
      KubbBinaryChoice<String>(
        options: const <KubbChoiceOption<String>>[
          KubbChoiceOption(value: 'single', title: 'Single-Out'),
          KubbChoiceOption(value: 'double', title: 'Double-Elimination'),
          KubbChoiceOption(value: 'consolation', title: 'Trostturnier'),
        ],
        selected: 'single',
        onChanged: (v) => picked = v,
      ),
    );
    await tester.tap(find.text('Trostturnier'));
    expect(picked, 'consolation');
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
  });
}
