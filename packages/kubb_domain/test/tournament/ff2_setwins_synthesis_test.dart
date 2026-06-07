import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

/// FF2 / Finding B: the standings synthesis must reconstruct REAL set wins
/// in classic mode so client and server (tournament_pool_standings, CF2)
/// standings agree for best-of-3. The EKC path must stay on the historical
/// single-set synthesis.

const _chain = TiebreakerChain([
  TiebreakerCriterion.totalPoints,
  TiebreakerCriterion.wins,
  TiebreakerCriterion.kubbDifference,
]);

void main() {
  group('tournamentMatchResultFromFinalScore', () {
    test('classic: reconstructs real set wins (Bo3 2:1)', () {
      final r = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 17,
        finalScoreB: 11,
        scoring: TournamentScoring.classic,
        setsWonA: 2,
        setsWonB: 1,
      );
      // Real set wins, NOT a single match win (1/0).
      expect(r.score.setsWonA, 2);
      expect(r.score.setsWonB, 1);
      // kubbs accumulate from final score unchanged (tiebreak source).
      final kA = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByA);
      final kB = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByB);
      expect(kA, 17);
      expect(kB, 11);
      expect(r.score.matchWinner, SetWinner.teamA);
    });

    test('classic: null set wins -> single-set fallback (match win)', () {
      final r = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 6,
        finalScoreB: 2,
        scoring: TournamentScoring.classic,
        // setsWonA/B omitted (null) = no projected set wins -> legacy
        // single-set path.
      );
      expect(r.score.sets, hasLength(1));
      expect(r.score.setsWonA, 1);
      expect(r.score.setsWonB, 0);
    });

    test('classic: 0:0 projected set wins -> empty score (server parity)', () {
      // FF2 review finding 2: when the RPC projects sets_won_a == 0 AND
      // sets_won_b == 0 (a match finalised with no agreed set), the server's
      // classic standings (tournament_pool_standings) award 0 points / 0
      // kubbs. The synthesis must mirror that with an EMPTY score, NOT a
      // synthetic winner set (which would have given the higher final score
      // 1 point -> 1/0 client-vs-server divergence).
      final r = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 6,
        finalScoreB: 2,
        scoring: TournamentScoring.classic,
        setsWonA: 0,
        setsWonB: 0,
      );
      expect(r.score.sets, isEmpty);
      expect(r.score.setsWonA, 0);
      expect(r.score.setsWonB, 0);
      expect(r.score.matchWinner, isNull);
      // No basekubbs accumulate either (server counts none for 0 agreed sets).
      final kA = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByA);
      final kB = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByB);
      expect(kA, 0);
      expect(kB, 0);
    });

    test('classic: 0:0 yields 0 points / 0 wins for both sides', () {
      final r = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 6,
        finalScoreB: 2,
        scoring: TournamentScoring.classic,
        setsWonA: 0,
        setsWonB: 0,
      );
      final rows = computeStandings(
        participantIds: const ['a', 'b'],
        results: [r],
        scoring: TournamentScoring.classic,
        tiebreaker: _chain,
      );
      final byId = {for (final s in rows) s.participantId: s};
      // Both sides 0/0 — exactly the server's 0/0 classic projection.
      expect(byId['a']!.totalPoints, 0);
      expect(byId['b']!.totalPoints, 0);
      expect(byId['a']!.wins, 0);
      expect(byId['b']!.wins, 0);
    });

    test('classic: null set wins still uses single-set fallback (not 0:0)', () {
      // Guard the boundary: the empty-score path is ONLY for explicit 0:0
      // (both non-null). A null (unknown) projection keeps the legacy
      // single-set winner synthesis.
      final r = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 6,
        finalScoreB: 2,
        scoring: TournamentScoring.classic,
        // setsWonA/B null -> legacy path, NOT the 0:0 empty path.
      );
      expect(r.score.sets, hasLength(1));
      expect(r.score.setsWonA, 1);
    });

    test('ekc: never reconstructs sets even when set wins present', () {
      final withSets = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 17,
        finalScoreB: 11,
        scoring: TournamentScoring.ekc,
        setsWonA: 2,
        setsWonB: 1,
      );
      final withoutSets = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 17,
        finalScoreB: 11,
        scoring: TournamentScoring.ekc,
        // setsWonA/B omitted (null).
      );
      // EKC must be byte-identical regardless of projected set wins:
      // a single synthesised set carrying the full final score.
      expect(withSets.score.sets, hasLength(1));
      expect(withSets.score, withoutSets.score);
      expect(withSets.score.pointsForA, withoutSets.score.pointsForA);
    });
  });

  group('Bo3-classic parity with server (B4)', () {
    test('classic standings count set wins, not match wins', () {
      // Two Bo3 classic matches: a beats b 2:1, a beats c 2:0.
      final results = <TournamentMatchResult>[
        tournamentMatchResultFromFinalScore(
          participantA: 'a',
          participantB: 'b',
          finalScoreA: 17,
          finalScoreB: 11,
          scoring: TournamentScoring.classic,
          setsWonA: 2,
          setsWonB: 1,
        ),
        tournamentMatchResultFromFinalScore(
          participantA: 'a',
          participantB: 'c',
          finalScoreA: 12,
          finalScoreB: 3,
          scoring: TournamentScoring.classic,
          setsWonA: 2,
          setsWonB: 0,
        ),
      ];
      final rows = computeStandings(
        participantIds: const ['a', 'b', 'c'],
        results: results,
        scoring: TournamentScoring.classic,
        tiebreaker: _chain,
      );
      final byId = {for (final s in rows) s.participantId: s};
      // a won 4 sets total (2 + 2) -> 4 points (NOT 2 match wins).
      expect(byId['a']!.totalPoints, 4);
      // b won 1 set against a -> 1 point (NOT 0).
      expect(byId['b']!.totalPoints, 1);
      // c won 0 sets -> 0 points.
      expect(byId['c']!.totalPoints, 0);
      // Match wins (the `wins` field) still reflect match outcomes.
      expect(byId['a']!.wins, 2);
      expect(byId['b']!.wins, 0);
    });

    test('without the fix (single set) the loser of a Bo3 would get 0', () {
      // Demonstrates the regression the fix removes: single-set synthesis
      // gives the 2:1 loser 0 classic points instead of 1.
      final single = tournamentMatchResultFromFinalScore(
        participantA: 'a',
        participantB: 'b',
        finalScoreA: 17,
        finalScoreB: 11,
        scoring: TournamentScoring.classic,
        // setsWonA/B omitted (null) forces the legacy single-set path.
      );
      final rows = computeStandings(
        participantIds: const ['a', 'b'],
        results: [single],
        scoring: TournamentScoring.classic,
        tiebreaker: _chain,
      );
      final byId = {for (final s in rows) s.participantId: s};
      expect(byId['b']!.totalPoints, 0); // legacy = match win count
    });
  });
}
