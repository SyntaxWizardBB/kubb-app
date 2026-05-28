// Widget regression for Mängel #2.4 (R9-F-10 / R19-F-05):
// The team-create form must scroll around the software keyboard so the
// submit button stays reachable when the IME inflates `viewInsets.bottom`.
// We fake a 320px keyboard insert and assert (a) the form scrolls,
// (b) the submit button is not clipped by the bottom inset.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_app/features/team/presentation/team_create_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _NoopTeamRepo implements TeamRepository {
  @override
  Future<TeamId> createTeam({
    required String displayName,
    required LeagueMembership leagueMembership,
    String? logoUrl,
    String? country,
  }) async =>
      const TeamId('noop');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pumpWithInsets(
  WidgetTester tester, {
  required double bottomInset,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/teams/new',
    routes: [
      GoRoute(
        path: '/teams/new',
        builder: (_, _) => const TeamCreateScreen(),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail-${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        teamRepositoryProvider.overrideWithValue(_NoopTeamRepo()),
      ],
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
    'Mängel #2.4: form scrolls and submit stays reachable when keyboard '
    'insets the viewport',
    (tester) async {
      await _pumpWithInsets(tester, bottomInset: 320);

      // The body must be a Scrollable so users can reach the submit button
      // even when the keyboard eats half the viewport.
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      final submitFinder =
          find.widgetWithText(FilledButton, 'Team anlegen');
      expect(submitFinder, findsOneWidget);

      // Scroll the form upward so the submit button enters the viewport
      // (mirrors what the user would do once the keyboard pops up).
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // After scrolling, the submit button must be fully visible above the
      // 320px keyboard insert — no clipping by the IME.
      final buttonRect = tester.getRect(submitFinder);
      final viewportHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final keyboardTop = viewportHeight - 320;
      expect(
        buttonRect.bottom <= keyboardTop,
        isTrue,
        reason: 'submit button must sit above the 320px keyboard insert '
            '(bottom=${buttonRect.bottom}, keyboardTop=$keyboardTop)',
      );
    },
  );
}
