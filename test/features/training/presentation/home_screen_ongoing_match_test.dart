import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/tournament/application/my_active_match_provider.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/features/training/presentation/home_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Spec §4: the Home-Hub green match tile (`PitchCallBanner`,
/// cross-tournament) renders only while `myActiveTournamentMatchProvider`
/// yields a match. Null (as well as loading/error, same orElse branch) hides
/// it completely — there is no "Match-Modus / In Vorbereitung" placeholder.
MyActiveTournamentMatch _ongoing({String pitchLabel = '7'}) =>
    MyActiveTournamentMatch(
      tournament: const TournamentSummaryRef(
        tournamentId: TournamentId('t-1'),
        displayName: 'Sommercup',
        format: TournamentFormat.roundRobin,
        status: TournamentStatus.live,
        startedAt: null,
        completedAt: null,
        participantCount: 8,
      ),
      active: MyActiveMatch(
        match: const TournamentMatchRef(
          matchId: TournamentMatchId('m-1'),
          tournamentId: TournamentId('t-1'),
          roundNumber: 1,
          matchNumberInRound: 2,
          participantA: TournamentParticipantId('p-me'),
          participantB: TournamentParticipantId('p-opp'),
          status: TournamentMatchStatus.awaitingResults,
          consensusRound: 0,
          pitchNumber: 7,
        ),
        pitchLabel: pitchLabel,
        opponentName: 'Team Birke',
      ),
    );

void main() {
  Future<GoRouter> pump(
    WidgetTester tester, {
    MyActiveTournamentMatch? ongoingMatch,
  }) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/tournament/:id/match/:matchId',
          builder: (_, _) => const Scaffold(body: Text('match-detail')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          displayProfileProvider.overrideWithValue(
            const DisplayProfile(userId: 'p1', displayName: 'Lukas'),
          ),
          recentActivityProvider
              .overrideWith((ref) async => const <RecentSessionView>[]),
          crashRecoveryProvider.overrideWith((ref) async => null),
          organizerTileVisibleProvider.overrideWith((ref) async => false),
          myActiveTournamentMatchProvider.overrideWith(
            (ref) => AsyncValue<MyActiveTournamentMatch?>.data(ongoingMatch),
          ),
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
    await tester.pump();
    return router;
  }

  testWidgets('renders the green pitch tile with the pitch when active',
      (tester) async {
    await pump(tester, ongoingMatch: _ongoing());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pitch-call-banner')), findsOneWidget);
    // The green tile shows the assigned pitch and the opponent.
    expect(find.text('Dein Platz: Pitch 7 — leg los!'), findsOneWidget);
    expect(find.text('Gegen Team Birke'), findsOneWidget);
    // The old placeholder + "Laufendes Match" card are gone.
    expect(find.text('Match-Modus'), findsNothing);
    expect(find.text('Laufendes Match'), findsNothing);
  });

  testWidgets('tapping the tile opens the match-detail screen', (tester) async {
    final router = await pump(tester, ongoingMatch: _ongoing());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spiel öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('match-detail'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/tournament/t-1/match/m-1',
    );
  });

  testWidgets('hides the tile completely when the provider yields null',
      (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pitch-call-banner')), findsNothing);
    expect(find.text('Match-Modus'), findsNothing);
    // The rest of the home layout is unaffected.
    expect(find.text('Hallo, Lukas.'), findsOneWidget);
    expect(find.text('Meine Teams'), findsOneWidget);
  });
}
