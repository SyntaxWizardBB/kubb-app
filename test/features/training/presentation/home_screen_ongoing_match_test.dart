import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/tournament/application/my_active_match_provider.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/features/training/presentation/home_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// P5-C (ADR-0032 §7): the Home screen renders the ongoing tournament-match
/// tile only while `myActiveTournamentMatchProvider` yields a match — null
/// (as well as loading/error, same orElse branch) hides it completely.
MyActiveTournamentMatch _ongoing() => const MyActiveTournamentMatch(
      tournament: TournamentSummaryRef(
        tournamentId: TournamentId('t-1'),
        displayName: 'Sommercup',
        format: TournamentFormat.roundRobin,
        status: TournamentStatus.live,
        startedAt: null,
        completedAt: null,
        participantCount: 8,
      ),
      active: MyActiveMatch(
        match: TournamentMatchRef(
          matchId: TournamentMatchId('m-1'),
          tournamentId: TournamentId('t-1'),
          roundNumber: 1,
          matchNumberInRound: 2,
          participantA: TournamentParticipantId('p-me'),
          participantB: TournamentParticipantId('p-opp'),
          status: TournamentMatchStatus.awaitingResults,
          consensusRound: 0,
        ),
        pitchLabel: '2',
        opponentName: 'Team Birke',
      ),
    );

void main() {
  Future<void> pump(
    WidgetTester tester, {
    MyActiveTournamentMatch? ongoingMatch,
  }) async {
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
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the ongoing-match tile when a match is active',
      (tester) async {
    await pump(tester, ongoingMatch: _ongoing());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home.ongoingMatch')), findsOneWidget);
    expect(find.text('Laufendes Match'), findsOneWidget);
    // Tournament + opponent context on the subtitle.
    expect(find.text('Sommercup · gegen Team Birke'), findsOneWidget);
  });

  testWidgets('hides the tile completely when the provider yields null',
      (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home.ongoingMatch')), findsNothing);
    expect(find.text('Laufendes Match'), findsNothing);
    // The rest of the home layout is unaffected.
    expect(find.text('Hallo, Lukas.'), findsOneWidget);
    expect(find.text('Meine Teams'), findsOneWidget);
  });
}
