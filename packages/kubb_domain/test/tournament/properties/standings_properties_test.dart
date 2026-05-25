import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../_support/tournament_generators.dart';

const _chain = TiebreakerChain(
  [TiebreakerCriterion.totalPoints, TiebreakerCriterion.random],
  randomSeed: 7,
);

List<TournamentMatchResult> _buildResults(
  List<String> ids,
  List<(int, int, MatchEkcScore, bool)> raw,
) {
  return [
    for (final (rawA, rawB, score, isBye) in raw)
      if (isBye)
        TournamentMatchResult(
          participantA: ids[rawA % ids.length],
          participantB: null,
          score: MatchEkcScore(const []),
        )
      else if (ids[rawA % ids.length] != ids[rawB % ids.length])
        TournamentMatchResult(
          participantA: ids[rawA % ids.length],
          participantB: ids[rawB % ids.length],
          score: score,
        ),
  ];
}

void main() {
  group('computeStandings properties', () {
    Glados<List<String>>(any.participantIds(max: 12)).test(
        'with no results, returns one zeroed entry per participant',
        (ids) {
      final standings = computeStandings(
        participantIds: ids,
        results: const [],
        tiebreaker: _chain,
      );
      expect(standings, hasLength(ids.length));
      expect(standings.map((s) => s.participantId).toSet(), ids.toSet());
      for (final s in standings) {
        expect(s.totalPoints, 0);
        expect(s.wins, 0);
        expect(s.kubbsScored, 0);
        expect(s.kubbsConceded, 0);
      }
    });

    Glados2<List<String>, List<(int, int, MatchEkcScore, bool)>>(
      any.participantIds(max: 8),
      any.list(
        any.combine4<int, int, MatchEkcScore, bool,
            (int, int, MatchEkcScore, bool)>(
          any.intInRange(0, 8),
          any.intInRange(0, 8),
          any.matchEkcScore(maxSets: 3),
          any.bool,
          (a, b, score, bye) => (a, b, score, bye),
        ),
      ),
    ).test('conserves the sum of pointsForA + pointsForB across all results',
        (ids, raw) {
      final results = _buildResults(ids, raw);
      final standings = computeStandings(
        participantIds: ids,
        results: results,
        tiebreaker: _chain,
      );
      final expected = results.fold<int>(0, (acc, r) {
        if (r.participantB == null) return acc;
        return acc + r.score.pointsForA + r.score.pointsForB;
      });
      final actual = standings.fold<int>(0, (s, x) => s + x.totalPoints);
      expect(actual, expected);
    });

    Glados2<List<String>, List<(int, int, MatchEkcScore, bool)>>(
      any.participantIds(max: 8),
      any.list(
        any.combine4<int, int, MatchEkcScore, bool,
            (int, int, MatchEkcScore, bool)>(
          any.intInRange(0, 8),
          any.intInRange(0, 8),
          any.matchEkcScore(maxSets: 3),
          any.bool,
          (a, b, score, bye) => (a, b, score, bye),
        ),
      ),
    ).test('returns exactly one entry per input participant', (ids, raw) {
      final standings = computeStandings(
        participantIds: ids,
        results: _buildResults(ids, raw),
        tiebreaker: _chain,
      );
      expect(standings, hasLength(ids.length));
      final outputIds = standings.map((s) => s.participantId).toList();
      expect(outputIds.toSet(), hasLength(outputIds.length));
      expect(outputIds.toSet(), ids.toSet());
    });
  });
}
