import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_standings_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

ParticipantStats _stat(String id,
    {int total = 0, int wins = 0, int scored = 0, int conceded = 0}) {
  return ParticipantStats(
    participantId: id,
    totalPoints: total,
    wins: wins,
    kubbsScored: scored,
    kubbsConceded: conceded,
    opponentIds: const <String>[],
    opponentTotalPointsLookup: const <String, int>{},
    headToHeadLookup: const <String, int>{},
  );
}

TournamentParticipant _participant(String id, String displayName) {
  return TournamentParticipant(
    participantId: id,
    userId: null,
    nickname: null,
    displayName: displayName,
    registrationStatus: TournamentParticipantStatus.approved,
    seed: null,
    registeredAt: DateTime.utc(2026),
    respondedAt: null,
  );
}

TournamentDetail _detail(
  List<TournamentParticipant> participants, {
  int teamSize = 1,
}) {
  return TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'Sommer-Cup',
      createdByUserId: 'u-creator',
      clubId: null,
      teamSize: teamSize,
      maxTeamSize: teamSize,
      minParticipants: 2,
      maxParticipants: 8,
      format: TournamentFormat.roundRobin,
      scoring: TournamentScoring.ekc,
      matchFormatConfig: const <String, Object?>{},
      tiebreakerOrder: const <String>[],
      byePoints: 0,
      forfeitPoints: 0,
      status: TournamentStatus.live,
      publishedAt: null,
      startedAt: null,
      completedAt: null,
    ),
    participants: participants,
    matches: const <TournamentMatchRef>[],
    auditTail: const <TournamentAuditEvent>[],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ParticipantStats> rows,
  String? me,
  List<TournamentParticipant> participants = const <TournamentParticipant>[],
  int teamSize = 1,
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/t-1/standings',
    routes: [
      GoRoute(
        path: '/tournament/:id/standings',
        builder: (_, s) => TournamentStandingsScreen(
          tournamentId: s.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/matches',
        builder: (_, _) => const Scaffold(body: Text('matches')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentStandingsProvider(const TournamentId('t-1'))
            .overrideWith((_) async => rows),
        tournamentDetailProvider(const TournamentId('t-1'))
            .overrideWith((_) async => _detail(participants, teamSize: teamSize)),
        currentUserIdProvider.overrideWith((_) => me),
        // The standings view now subscribes to the per-tournament channel as
        // its realtime anchor (W1-T14); give it a fake transport + remote.
        tournamentRemoteProvider.overrideWithValue(
          FakeTournamentRemote(
            initialUser: const UserId('me'),
            realtime: FakeRealtimeChannel(),
          ),
        ),
        realtimeChannelProvider.overrideWithValue(FakeRealtimeChannel()),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty standings shows empty-state copy', (tester) async {
    await _pump(tester, rows: const <ParticipantStats>[]);
    expect(find.text('Noch keine Ergebnisse.'), findsOneWidget);
  });

  testWidgets('populated standings render display names from the roster',
      (tester) async {
    await _pump(
      tester,
      rows: <ParticipantStats>[
        _stat('alpha', total: 9, wins: 3, scored: 12, conceded: 5),
        _stat('beta', total: 6, wins: 2, scored: 8, conceded: 8),
        _stat('gamma', total: 3, wins: 1, scored: 6, conceded: 10),
      ],
      participants: <TournamentParticipant>[
        _participant('alpha', 'Alice'),
        _participant('beta', 'Bob'),
        _participant('gamma', 'Gamma-Team'),
      ],
    );
    expect(find.text('Endrangliste'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Gamma-Team'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    // Two rows render rank "1" + wins "1" (gamma), so we just sanity-check
    // that *some* "1" shows up rather than fight the duplicate.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('solo tournament labels the name column "Spieler"',
      (tester) async {
    await _pump(
      tester,
      rows: <ParticipantStats>[_stat('alpha', total: 9)],
      participants: <TournamentParticipant>[_participant('alpha', 'Alice')],
    );
    expect(find.text('Spieler'), findsOneWidget);
    expect(find.text('Team'), findsNothing);
  });

  testWidgets('team tournament labels the name column "Team"', (tester) async {
    await _pump(
      tester,
      teamSize: 2,
      rows: <ParticipantStats>[_stat('alpha', total: 9)],
      participants: <TournamentParticipant>[_participant('alpha', 'Alice')],
    );
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Spieler'), findsNothing);
  });

  testWidgets('falls back to tournamentParticipantUnknown when the roster '
      'has no display_name', (tester) async {
    await _pump(
      tester,
      rows: <ParticipantStats>[
        _stat('alpha', total: 9, wins: 3, scored: 12, conceded: 5),
      ],
    );
    expect(find.text('Unbekannt'), findsOneWidget);
  });
}
