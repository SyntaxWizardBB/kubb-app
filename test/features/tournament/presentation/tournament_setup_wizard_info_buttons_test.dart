import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Minimal remote stub — the info-button tests never submit, so every RPC
/// throws if it is ever reached.
class _UnusedRemote implements TournamentRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Seeds the step-1 fields a wizard needs so it renders on the Stammdaten
/// step without redirects.
class _SeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => super.build().copyWith(
        displayName: 'Frühlingscup',
        location: 'Brügg',
        eventStartsAt: DateTime(2026, 6, 20, 10),
        registrationClosesAt: DateTime(2026, 6, 18, 18),
      );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: TournamentRoutes.newTournament,
    routes: [
      GoRoute(
        path: TournamentRoutes.newTournament,
        builder: (_, _) => const TournamentSetupWizard(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(_UnusedRemote()),
        tournamentConfigControllerProvider.overrideWith(_SeededController.new),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Finds the info-glyph whose tooltip matches [title], scrolls it into view,
/// taps it, and asserts the explainer dialog shows [bodyFragment].
Future<void> _openAndExpect(
  WidgetTester tester, {
  required String title,
  required String bodyFragment,
}) async {
  final button = find.descendant(
    of: find.byType(InfoIconButton),
    matching: find.byTooltip(title),
  );
  expect(button, findsOneWidget, reason: 'missing info button "$title"');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();

  expect(find.widgetWithText(AlertDialog, title), findsOneWidget);
  expect(find.textContaining(bodyFragment), findsOneWidget);

  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Turniername info button opens its explainer', (tester) async {
    await _pump(tester);
    await _openAndExpect(
      tester,
      title: 'Name des Turniers',
      bodyFragment: 'unter dem dein Turnier',
    );
  });

  testWidgets('Scoring info button opens its explainer', (tester) async {
    await _pump(tester);
    await _openAndExpect(
      tester,
      title: 'Zählweise der Sätze',
      bodyFragment: 'Feldkubb',
    );
  });

  testWidgets('Sureshot toggle carries an info button', (tester) async {
    await _pump(tester);
    await _openAndExpect(
      tester,
      title: 'Sonderregel Sureshot',
      bodyFragment: 'durch die Beine',
    );
  });

  testWidgets('shared participant-info section info button opens',
      (tester) async {
    await _pump(tester);
    await _openAndExpect(
      tester,
      title: 'Hinweise für Teilnehmer',
      bodyFragment: 'Freitextfelder',
    );
  });
}
