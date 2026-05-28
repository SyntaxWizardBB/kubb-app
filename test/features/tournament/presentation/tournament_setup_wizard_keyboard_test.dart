// Widget regression for Mängel #2.4 (BH-C-03, W4.1-E):
// The tournament-setup wizard must scroll around the software keyboard so
// the per-step "Weiter" button stays reachable when the IME inflates
// `viewInsets.bottom`. PageView/Stepper variant: every step is its own
// SingleChildScrollView — the assertion below targets the active step's
// padding.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _NoopRemote implements TournamentRemote {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  Future<List<TournamentSummaryRef>> listTournaments({
    TournamentStatus? statusFilter,
    int limit = 50,
  }) async =>
      const <TournamentSummaryRef>[];

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async => null;
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
        tournamentRemoteProvider.overrideWithValue(_NoopRemote()),
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
    'Mängel #2.4: wizard step scroll padding tracks 320px keyboard insert',
    (tester) async {
      await _pumpWithInsets(tester, bottomInset: 320);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.resizeToAvoidBottomInset, isTrue);

      // Active step lives inside a SingleChildScrollView whose bottom
      // padding must absorb the IME insert + the base step gap.
      final scrollFinder = find.byType(SingleChildScrollView);
      expect(scrollFinder, findsOneWidget);

      final view = tester.widget<SingleChildScrollView>(scrollFinder);
      expect(
        view.padding!.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(320),
        reason: 'wizard step padding must absorb the keyboard insert',
      );
    },
  );
}
