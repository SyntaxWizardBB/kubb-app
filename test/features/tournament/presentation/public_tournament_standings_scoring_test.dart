import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_realtime.dart';
import 'package:kubb_app/features/tournament/presentation/public/public_tournament_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// FF2 / Finding A: the anon spectator standings must use the tournament's
/// real scoring mode (now projected by public_tournament_get). A classic
/// tournament renders classic totals (set wins), an EKC tournament keeps
/// the historical EKC totals.

const _tid = TournamentId('t-1');

PublicTournamentDetail _detail({
  required TournamentScoring scoring,
}) {
  PublicMatchDetail match({
    required String id,
    required String a,
    required String b,
    required String winner,
    required int fsA,
    required int fsB,
    int? setsWonA,
    int? setsWonB,
  }) {
    return PublicMatchDetail(
      matchId: TournamentMatchId(id),
      tournamentId: _tid,
      roundNumber: 1,
      matchNumberInRound: 1,
      participantA: TournamentParticipantId(a),
      participantB: TournamentParticipantId(b),
      status: TournamentMatchStatus.finalized,
      consensusRound: 1,
      winnerParticipant: TournamentParticipantId(winner),
      finalScoreA: fsA,
      finalScoreB: fsB,
      setsWonA: setsWonA,
      setsWonB: setsWonB,
      phase: 'group',
    );
  }

  return PublicTournamentDetail(
    tournament: PublicTournamentHeader(
      tournamentId: _tid,
      displayName: 'Cup',
      teamSize: 1,
      format: TournamentFormat.roundRobin,
      scoring: scoring,
      status: TournamentStatus.live,
      matchFormatConfig: const <String, Object?>{'format': 'best_of_3'},
    ),
    matches: <PublicMatchDetail>[
      // Bo3: A beats B 2:1, basekubbs 17:11.
      match(
        id: 'm-1',
        a: 'p-a',
        b: 'p-b',
        winner: 'p-a',
        fsA: 17,
        fsB: 11,
        setsWonA: 2,
        setsWonB: 1,
      ),
    ],
    roster: const <PublicRosterEntry>[
      PublicRosterEntry(
          slotId: 's-a',
          participantId: 'p-a',
          slotIndex: 1,
          displayName: 'Alice'),
      PublicRosterEntry(
          slotId: 's-b',
          participantId: 'p-b',
          slotIndex: 1,
          displayName: 'Bob'),
    ],
    participantCount: 2,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required TournamentScoring scoring,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicTournamentDetailProvider(_tid).overrideWith(
          (ref) async => _detail(scoring: scoring),
        ),
        // No realtime events in the test — a stream that never emits.
        publicTournamentEventsProvider(_tid).overrideWith(
          (ref) => const Stream<PublicTournamentEvent>.empty(),
        ),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PublicTournamentScreen(tournamentId: _tid),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Switch to the Rangliste (standings) tab.
  await tester.tap(find.text('Rangliste'));
  await tester.pumpAndSettle();
}

/// Reads the standings cell text for a given participant name. The cell is
/// rendered as `'<points>  ·  <wins>W  ·  <diff>'` next to the name.
String _statsLineFor(WidgetTester tester, String name) {
  final row = find.ancestor(
    of: find.text(name),
    matching: find.byType(Row),
  );
  final texts = find
      .descendant(of: row.first, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();
  return texts.firstWhere((t) => t.contains('·') && t.contains('W'));
}

void main() {
  testWidgets('FF2/A3: classic tournament renders classic (set-win) totals',
      (tester) async {
    await _pump(tester, scoring: TournamentScoring.classic);
    // Classic: A won 2 sets -> 2 points, B won 1 set -> 1 point.
    expect(_statsLineFor(tester, 'Alice'), startsWith('2  ·'));
    expect(_statsLineFor(tester, 'Bob'), startsWith('1  ·'));
  });

  testWidgets('FF2/A3: EKC tournament keeps EKC totals (final-score based)',
      (tester) async {
    await _pump(tester, scoring: TournamentScoring.ekc);
    // EKC: single-set synthesis -> A = 17 basekubbs + 3 winner bonus = 20,
    // B = 11 basekubbs + 0 = 11. (Unchanged from pre-FF2 behaviour.)
    expect(_statsLineFor(tester, 'Alice'), startsWith('20  ·'));
    expect(_statsLineFor(tester, 'Bob'), startsWith('11  ·'));
  });
}
