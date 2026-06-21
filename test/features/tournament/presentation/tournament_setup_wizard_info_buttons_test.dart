import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';
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
        clubChoiceMade: true,
        location: 'Brügg',
        venueAddress: 'Sportplatz Brügg',
        eventStartsAt: DateTime(2026, 6, 20, 10),
        registrationClosesAt: DateTime(2026, 6, 18, 18),
        checkinUntil: DateTime(2026, 6, 20, 9, 30),
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
/// taps it, and asserts the explainer sheet shows the [title] and
/// [bodyFragment]. Dismisses the sheet afterwards by tapping the scrim.
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

  expect(find.byType(KubbBottomSheet), findsOneWidget);
  expect(find.widgetWithText(KubbBottomSheet, title), findsOneWidget);
  expect(find.textContaining(bodyFragment), findsOneWidget);

  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

/// Turns on the Stammdaten step's help mode so the retained info glyphs
/// (Scoring + the Spielregeln switches) surface.
Future<void> _enableHelp(WidgetTester tester) async {
  await tester.tap(find.text('Erklärungen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Stammdaten info glyphs stay hidden until help mode is on',
      (tester) async {
    await _pump(tester);
    // The Stammdaten step is quiet by default — no info glyphs on the
    // self-explanatory fields, and the retained ones stay folded away.
    expect(find.byType(InfoIconButton), findsNothing);
    await _enableHelp(tester);
    expect(find.byType(InfoIconButton), findsWidgets);
  });

  testWidgets('Scoring info button opens its explainer in help mode',
      (tester) async {
    await _pump(tester);
    await _enableHelp(tester);
    await _openAndExpect(
      tester,
      title: 'Zählweise der Sätze',
      bodyFragment: 'Feldkubb',
    );
  });

  testWidgets('Sureshot toggle carries an info button in help mode',
      (tester) async {
    await _pump(tester);
    await _enableHelp(tester);
    await _openAndExpect(
      tester,
      title: 'Sonderregel Sureshot',
      bodyFragment: 'durch die Beine',
    );
  });

  testWidgets('participants step number fields carry info buttons',
      (tester) async {
    await _pump(tester);
    // The seeded controller fills every step-1 field, so a single "Weiter"
    // lands on the Teilnehmer step.
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();

    // The participant fields surface their info glyphs only in help mode;
    // turn it on via the step's "Erklärungen" toggle first.
    expect(find.byType(InfoIconButton), findsNothing);
    await tester.tap(find.text('Erklärungen'));
    await tester.pumpAndSettle();

    await _openAndExpect(
      tester,
      title: 'Kleinste Teamgrösse',
      bodyFragment: 'mindestens haben muss',
    );
    await _openAndExpect(
      tester,
      title: 'Grösste Teamgrösse',
      bodyFragment: 'höchstens haben darf',
    );
    await _openAndExpect(
      tester,
      title: 'Teilnehmer-Obergrenze',
      bodyFragment: 'Warteliste',
    );
  });

  testWidgets('format step glyphs stay hidden until help mode is on',
      (tester) async {
    await _pump(tester);
    // Two "Weiter" taps: Stammdaten -> Teilnehmer -> Format.
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();

    // The format step is quiet by default — even the retained glyphs only
    // surface once the step's help mode is on.
    expect(find.byType(InfoIconButton), findsNothing);
    await _enableHelp(tester);
    expect(find.byType(InfoIconButton), findsWidgets);
  });

  testWidgets('format step mode and Vorrunde carry info buttons in help mode',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await _enableHelp(tester);

    await _openAndExpect(
      tester,
      title: 'Wie das Turnier aufgebaut ist',
      bodyFragment: 'gewohnten Ablauf',
    );
    await _openAndExpect(
      tester,
      title: 'Wie die Vorrunde läuft',
      bodyFragment: 'bevor das K.-o. beginnt',
    );
  });

  testWidgets('self-explanatory format fields lost their info glyphs',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await _enableHelp(tester);

    // Max. Sätze, Match-Zeit and Pause are self-explanatory now — their glyphs
    // are gone even with help on. The tooltips no longer resolve to a button.
    for (final title in <String>[
      'Sätze pro Spiel (Vorrunde)',
      'Zeit pro Spiel',
      'Pause nach einem Spiel',
    ]) {
      expect(
        find.descendant(
          of: find.byType(InfoIconButton),
          matching: find.byTooltip(title),
        ),
        findsNothing,
        reason: 'glyph "$title" should be gone',
      );
    }
  });

  testWidgets('Schoch rounds slider carries an info button in help mode',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await _enableHelp(tester);

    // Switch the Vorrunde to Schoch so its rounds section renders.
    await tester.tap(find.text('Schoch'));
    await tester.pumpAndSettle();

    await _openAndExpect(
      tester,
      title: 'Anzahl Schoch-Runden',
      bodyFragment: 'nach Tabellenstand',
    );
  });

  testWidgets('KO system offers a compare-models text link, not a 2nd glyph',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await _enableHelp(tester);

    // The detailed three-model sheet hangs off a discreet text link below the
    // KO choice — tapping it opens the explainer. No second "i"-glyph.
    final link = find.text('Modelle vergleichen');
    expect(link, findsOneWidget);
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Welcher zweite Baum?'), findsOneWidget);
  });
}
