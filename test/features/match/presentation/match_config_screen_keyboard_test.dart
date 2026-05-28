// Widget regression for Mängel #2.4 (BH-C-03, W4.1-E):
// The match-config screen must scroll around the software keyboard so the
// "Match starten" submit stays reachable when the IME inflates
// `viewInsets.bottom`. We fake a 320px keyboard insert and assert
// (a) the body is a Scrollable, (b) the bottom padding includes the IME
// inset, so the FilledButton cannot be clipped by the keyboard.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/match/presentation/match_config_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

Future<void> _pumpWithInsets(
  WidgetTester tester, {
  required double bottomInset,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/match/new',
    routes: [
      GoRoute(
        path: '/match/new',
        builder: (_, _) => const MatchConfigScreen(),
      ),
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Mängel #2.4: match-config scroll padding tracks 320px keyboard insert',
    (tester) async {
      await _pumpWithInsets(tester, bottomInset: 320);

      // Body must be a Scrollable so users can reach the submit button.
      final scrollFinder = find.byType(SingleChildScrollView);
      expect(scrollFinder, findsOneWidget);

      // The scroll padding must include the keyboard insert + the base
      // 32px gap (KubbTokens.space8). Without the W4.1-E patch the
      // bottom padding was just KubbTokens.space8 (32) — clipping the
      // submit button under the IME.
      final view = tester.widget<SingleChildScrollView>(scrollFinder);
      expect(
        view.padding!.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(320),
        reason: 'scroll padding must absorb the keyboard insert',
      );
    },
  );
}
