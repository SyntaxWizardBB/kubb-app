import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_nav.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<int?> pumpNav(
    WidgetTester tester, {
    required int currentIndex,
  }) async {
    int? tapped;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: const SizedBox.shrink(),
            bottomNavigationBar: KubbBottomNav(
              currentIndex: currentIndex,
              onTap: (i) => tapped = i,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tapped;
  }

  testWidgets('renders three tab labels and no profile tab', (tester) async {
    await pumpNav(tester, currentIndex: 1);
    final ctx = tester.element(find.byType(KubbBottomNav));
    final l = AppLocalizations.of(ctx);
    expect(find.text(l.homeFabLabel), findsOneWidget);
    expect(find.text(l.homeAppTitle), findsOneWidget);
    expect(find.text(l.tournamentListEyebrow), findsOneWidget);
    // Profile is no longer a tab — it hangs off the home AppBar avatar.
    expect(find.text(l.profileTitle), findsNothing);
  });

  testWidgets('tabs fire their index, home sits in the middle (1)',
      (tester) async {
    int? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: const SizedBox.shrink(),
            bottomNavigationBar: KubbBottomNav(
              currentIndex: 1,
              onTap: (i) => captured = i,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(tester.element(find.byType(KubbBottomNav)));

    // Training on the left (index 0).
    await tester.tap(find.text(l.homeFabLabel));
    await tester.pumpAndSettle();
    expect(captured, 0);

    // Home in the middle (index 1).
    await tester.tap(find.text(l.homeAppTitle));
    await tester.pumpAndSettle();
    expect(captured, 1);

    // Tournaments on the right (index 2).
    await tester.tap(find.text(l.tournamentListEyebrow));
    await tester.pumpAndSettle();
    expect(captured, 2);
  });
}
