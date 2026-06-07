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
import 'package:kubb_app/features/tournament/presentation/widgets/ko_model_explainer_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Minimal remote stub: the format step never hits the network, so the wizard
/// only needs a remote that does not throw on construction.
class _StubRemote implements TournamentRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controller with the required Stammdaten (W1) pre-filled so the real wizard
/// can advance past the stricter step 1 to the format step.
class _StammdatenSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() {
    final start = DateTime(2026, 8, 1, 10);
    return super.build().copyWith(
          clubChoiceMade: true,
          location: 'Esp',
          venueAddress: 'Sportplatz Esp, Fislisbach',
          eventStartsAt: start,
          registrationClosesAt: start.subtract(const Duration(days: 7)),
          checkinUntil: start.subtract(const Duration(minutes: 30)),
        );
  }
}

/// Host that exposes the same info-icon affordance as `_StepFormat`: an
/// `IconButton(LucideIcons.info)` next to the KO-system label that opens the
/// shared [KoModelExplainerSheet]. Drives the modal directly so the test stays
/// independent of the full wizard navigation flow.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Row(
        children: [
          Expanded(child: Text(l10n.tournamentWizardKoSystemLabel)),
          IconButton(
            icon: const Icon(LucideIcons.info, size: 18),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: EdgeInsets.zero,
            tooltip: l10n.tournamentKoModelExplainerOpen,
            onPressed: () => KoModelExplainerSheet.show(context),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
      'info icon renders next to the KO-system label and is tappable',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const _Host(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final iconFinder = find.byIcon(LucideIcons.info);
    expect(iconFinder, findsOneWidget);

    // Touch target is >= 48dp per --bk-touch-min.
    final button = tester.getSize(find.byType(IconButton));
    expect(button.width, greaterThanOrEqualTo(48));
    expect(button.height, greaterThanOrEqualTo(48));
  });

  testWidgets(
      'tapping the info icon opens the explainer modal with title + all three '
      'models and characteristic excerpts', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const _Host(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.info));
    await tester.pumpAndSettle();

    // Title.
    expect(find.text('Welcher zweite Baum?'), findsOneWidget);

    // Three section headings.
    expect(find.text('Single-Out'), findsOneWidget);
    expect(find.text('Double-Elimination'), findsOneWidget);
    expect(find.text('Trostturnier'), findsOneWidget);

    // One characteristic excerpt per model.
    expect(
      find.textContaining('Eine Niederlage und du bist draussen'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Du musst zweimal verlieren'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Der Hauptbaum entscheidet Platz 1 und 2 endgültig'),
      findsOneWidget,
    );
  });

  // Regression guard for the *real* wiring in `_StepFormat`: mounts the full
  // wizard, navigates to the format step and taps the actual info icon there,
  // so removing/breaking the icon -> modal hook in the wizard fails this test.
  testWidgets(
      'real wizard format step exposes the info icon that opens the explainer',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(_StubRemote()),
        tournamentConfigControllerProvider
            .overrideWith(_StammdatenSeededController.new),
      ],
    );
    addTearDown(container.dispose);

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
      UncontrolledProviderScope(
        container: container,
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

    // Step 1 (Stammdaten) -> 2 (Teilnehmer) -> 3 (Format, holds the KO axis).
    await tester.enterText(find.byKey(const Key('wizardNameField')), 'Cup');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();

    // The real info icon next to the KO-system label opens the explainer.
    final infoIcon = find.byIcon(LucideIcons.info);
    expect(infoIcon, findsOneWidget);

    await tester.tap(infoIcon);
    await tester.pumpAndSettle();

    // The modal is open (its title is unique to the explainer sheet). The
    // model names also appear as KO-option labels behind the sheet, so scope
    // the heading assertions to the explainer widget itself.
    expect(find.text('Welcher zweite Baum?'), findsOneWidget);
    final sheet = find.byType(KoModelExplainerSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Single-Out')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Double-Elimination')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Trostturnier')),
      findsOneWidget,
    );
  });
}
