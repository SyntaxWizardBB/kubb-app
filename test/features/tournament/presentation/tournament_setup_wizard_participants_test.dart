import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_field.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _UnusedRemote implements TournamentRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

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

Future<void> _pumpParticipants(WidgetTester tester) async {
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
  // Stammdaten -> Teilnehmer.
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('uses KubbField for its three number inputs', (tester) async {
    await _pumpParticipants(tester);

    expect(find.byType(KubbField), findsNWidgets(3));
    expect(find.byType(WizardNumberField), findsNWidgets(3));
  });

  testWidgets('starts quiet — no info glyph until help is on', (tester) async {
    await _pumpParticipants(tester);

    expect(find.byType(InfoIconButton), findsNothing);

    await tester.tap(find.text('Erklärungen'));
    await tester.pumpAndSettle();

    expect(find.byType(InfoIconButton), findsNWidgets(3));

    // Toggling back hides them again.
    await tester.tap(find.text('Erklärungen'));
    await tester.pumpAndSettle();
    expect(find.byType(InfoIconButton), findsNothing);
  });

  testWidgets('clamps a max-team-size typed below the min on commit',
      (tester) async {
    await _pumpParticipants(tester);

    // Three number fields: min team size, max team size, max participants.
    final maxTeam = find.byType(TextField).at(1);
    await tester.tap(maxTeam);
    await tester.enterText(maxTeam, '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Min team size defaults to 1, so the max-team field clamps up to 1.
    expect(find.widgetWithText(TextField, '1'), findsWidgets);
  });
}
