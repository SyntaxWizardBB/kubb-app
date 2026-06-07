import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_bracket_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Bracket bracket,
  String id = 't-1',
  TournamentDetail? detail,
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/$id/bracket',
    routes: <GoRoute>[
      GoRoute(
        path: '/tournament/:id/bracket',
        builder: (_, s) => TournamentBracketScreen(
          tournamentId: s.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id',
        builder: (_, _) => const Scaffold(body: Text('detail')),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, _) => const Scaffold(body: Text('match')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentBracketProvider(TournamentId(id))
            .overrideWith((_) async => bracket),
        tournamentDetailProvider(TournamentId(id))
            .overrideWith((_) async => detail),
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

BracketPairing _pair(String a, String b) => (
      (seed: 1, participantId: a, isBye: false),
      (seed: 2, participantId: b, isBye: false),
    );

/// Minimal detail carrying just the participants whose ids appear in the
/// bracket, so the screen can build its CF3 name resolver. `team_size`
/// only affects the screen header (irrelevant here) — the display names
/// are already server-projected per participant.
TournamentDetail _detailWithNames(Map<String, String> idToName) {
  return TournamentDetail(
    tournament: const TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'CF3 Cup',
      createdByUserId: 'creator',
      clubId: null,
      teamSize: 1,
      maxTeamSize: 1,
      minParticipants: 2,
      maxParticipants: 8,
      format: TournamentFormat.singleElimination,
      scoring: TournamentScoring.ekc,
      matchFormatConfig: <String, Object?>{},
      tiebreakerOrder: <String>['pts'],
      byePoints: null,
      forfeitPoints: null,
      status: TournamentStatus.live,
      publishedAt: null,
      startedAt: null,
      completedAt: null,
    ),
    participants: <TournamentParticipant>[
      for (final entry in idToName.entries)
        TournamentParticipant(
          participantId: entry.key,
          userId: 'u-${entry.key}',
          nickname: entry.value,
          displayName: entry.value,
          registrationStatus: TournamentParticipantStatus.approved,
          seed: null,
          registeredAt: DateTime(2026),
          respondedAt: null,
        ),
    ],
    matches: const <TournamentMatchRef>[],
    auditTail: const <TournamentAuditEvent>[],
  );
}

void main() {
  testWidgets('renders empty-state when bracket has no rounds',
      (tester) async {
    await _pump(
      tester,
      bracket: const SingleEliminationBracket(rounds: <BracketRound>[]),
    );
    expect(find.text('KO noch nicht gestartet'), findsOneWidget);
    expect(find.byType(BracketCanvas), findsNothing);
  });

  testWidgets('renders BracketCanvas when bracket has rounds',
      (tester) async {
    final bracket = SingleEliminationBracket(
      rounds: <BracketRound>[
        BracketRound(
          number: 1,
          pairings: <BracketPairing>[_pair('alpha', 'beta')],
        ),
      ],
    );
    await _pump(tester, bracket: bracket);
    expect(find.byType(BracketCanvas), findsOneWidget);
    expect(find.text('KO noch nicht gestartet'), findsNothing);
  });

  testWidgets('AppBar title uses l10n key', (tester) async {
    await _pump(
      tester,
      bracket: const SingleEliminationBracket(rounds: <BracketRound>[]),
    );
    expect(find.text('KO-Bracket'), findsOneWidget);
  });

  testWidgets('empty ConsolationBracket shows the empty-state (DoD-10)',
      (tester) async {
    await _pump(
      tester,
      bracket: const ConsolationBracket(rounds: <BracketRound>[], thirdPlace: null),
    );
    expect(find.text('KO noch nicht gestartet'), findsOneWidget);
    expect(find.byType(BracketCanvas), findsNothing);
  });

  testWidgets('materialised ConsolationBracket shows the canvas (DoD-10)',
      (tester) async {
    final bracket = ConsolationBracket(
      rounds: <BracketRound>[
        BracketRound(
          number: 1,
          phase: BracketPhase.consolation,
          pairings: <BracketPairing>[_pair('cE', 'cF')],
        ),
      ],
      thirdPlace: null,
    );
    await _pump(tester, bracket: bracket);
    expect(find.byType(BracketCanvas), findsOneWidget);
    expect(find.text('KO noch nicht gestartet'), findsNothing);
  });

  testWidgets(
      'CF3: single tournament bracket shows player names, not participant ids',
      (tester) async {
    final bracket = SingleEliminationBracket(
      rounds: <BracketRound>[
        BracketRound(
          number: 1,
          pairings: <BracketPairing>[_pair('pa-alice', 'pa-bob')],
        ),
      ],
    );
    await _pump(
      tester,
      bracket: bracket,
      detail: _detailWithNames(<String, String>{
        'pa-alice': 'SingleAlice',
        'pa-bob': 'CaptainBob',
      }),
    );
    expect(find.text('SingleAlice'), findsOneWidget);
    expect(find.text('CaptainBob'), findsOneWidget);
    // The raw participant ids must NOT leak into the bracket cards.
    expect(find.text('pa-alice'), findsNothing);
    expect(find.text('pa-bob'), findsNothing);
  });

  testWidgets('CF3: team tournament bracket shows the team name (no regression)',
      (tester) async {
    final bracket = SingleEliminationBracket(
      rounds: <BracketRound>[
        BracketRound(
          number: 1,
          pairings: <BracketPairing>[_pair('pa-team1', 'pa-team2')],
        ),
      ],
    );
    await _pump(
      tester,
      bracket: bracket,
      detail: _detailWithNames(<String, String>{
        'pa-team1': 'Die Kubb-Kanonen',
        'pa-team2': 'Holzwürfel United',
      }),
    );
    expect(find.text('Die Kubb-Kanonen'), findsOneWidget);
    expect(find.text('Holzwürfel United'), findsOneWidget);
    expect(find.text('pa-team1'), findsNothing);
  });
}
