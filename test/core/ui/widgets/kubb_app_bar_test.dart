import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(appBar: child as PreferredSizeWidget),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders eyebrow and title together', (tester) async {
    await pump(
      tester,
      const KubbAppBar(eyebrow: 'Account', title: 'Profil'),
    );

    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('shows custom action in the right slot', (tester) async {
    await pump(
      tester,
      KubbAppBar(
        title: 'Home',
        actions: IconButton(
          key: const ValueKey('settings-btn'),
          icon: const Icon(Icons.settings),
          onPressed: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('settings-btn')), findsOneWidget);
  });

  testWidgets('exposes preferred size with status-bar padding', (tester) async {
    const bar = KubbAppBar(title: 'X');
    expect(bar.preferredSize.height, greaterThanOrEqualTo(64));
  });
}
