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

  testWidgets('renders all four tab labels', (tester) async {
    await pumpNav(tester, currentIndex: 0);
    final ctx = tester.element(find.byType(KubbBottomNav));
    final l = AppLocalizations.of(ctx);
    expect(find.text(l.homeAppTitle), findsOneWidget);
    expect(find.text(l.homeFabLabel), findsOneWidget);
    expect(find.text(l.tournamentListTitle), findsOneWidget);
    expect(find.text(l.profileTitle), findsOneWidget);
  });

  testWidgets('tapping a tab fires onTap with its index', (tester) async {
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
              currentIndex: 0,
              onTap: (i) => captured = i,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(tester.element(find.byType(KubbBottomNav)));
    await tester.tap(find.text(l.tournamentListTitle));
    await tester.pumpAndSettle();
    expect(captured, 2);
  });
}
