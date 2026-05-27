import 'package:kubb_domain/src/tournament/league_points_engine.dart';
import 'package:test/test.dart';

/// Builds a contiguous standings list of [n] participants, placement 1..n.
/// If [byePlacement] is set, the row at that 1-indexed placement is flagged
/// as a bye recipient (FR-PAIR-7 / ADR-0024 §2).
List<FinalStandingsRow> _standings(int n, {int? byePlacement}) =>
    List<FinalStandingsRow>.generate(
      n,
      (i) => FinalStandingsRow(
        participantId: 'P${i + 1}',
        placement: i + 1,
        receivedBye: (i + 1) == byePlacement,
      ),
    );

/// Default Stufungs-Bonus from FR-POINTS-1, cumulative top-down.
/// 1..4 → +4 per rank above the next tier ⇒ +16 at place 1, +12 at place 5,
/// etc. Used by the placement / bonus tests below.
const Map<int, int> _frPointsBonus = {
  1: 16,
  2: 12,
  3: 8,
  4: 4,
  5: 9,
  6: 6,
  7: 3,
  8: 0,
};

void main() {
  group('LeaguePointsEngine.compute', () {
    const engine = LeaguePointsEngine();

    test('TF=1.0, LF=1.0 → final == base (identity)', () {
      const config = LeaguePointsConfig(
        bonusByPlacement: _frPointsBonus,
      );
      final awards = engine.compute(
        finalStandings: _standings(8),
        leagueId: 'L1',
        config: config,
      );

      expect(awards, hasLength(8));
      for (final a in awards) {
        expect(a.finalPoints, closeTo(a.basePoints, 1e-9));
      }
    });

    test('TF=2.0, LF=1.5 → final == base × 3.0', () {
      const config = LeaguePointsConfig(
        tournamentFactor: 2,
        leagueFactor: 1.5,
        bonusByPlacement: _frPointsBonus,
      );
      final awards = engine.compute(
        finalStandings: _standings(8),
        leagueId: 'L1',
        config: config,
      );

      for (final a in awards) {
        expect(a.finalPoints, closeTo(a.basePoints * 3.0, 0.01));
      }
    });

    test('placement 1 with bonus → basePoints == N + bonus_1', () {
      const config = LeaguePointsConfig(bonusByPlacement: _frPointsBonus);
      final awards = engine.compute(
        finalStandings: _standings(8),
        leagueId: 'L1',
        config: config,
      );

      final first = awards.firstWhere((a) => a.placement == 1);
      // Base = (N − place + 1) + bonus = (8 − 1 + 1) + 16 = 24.
      expect(first.basePoints, closeTo(8 + _frPointsBonus[1]!, 1e-9));
    });

    test(
        'property: sum of finalPoints is permutation-invariant on input order',
        () {
      const config = LeaguePointsConfig(
        tournamentFactor: 1.25,
        leagueFactor: 1.1,
        bonusByPlacement: _frPointsBonus,
      );
      final ordered = _standings(8);
      final shuffled = [...ordered]..shuffle();

      final sumOrdered = engine
          .compute(
            finalStandings: ordered,
            leagueId: 'L1',
            config: config,
          )
          .fold<double>(0, (s, a) => s + a.finalPoints);
      final sumShuffled = engine
          .compute(
            finalStandings: shuffled,
            leagueId: 'L1',
            config: config,
          )
          .fold<double>(0, (s, a) => s + a.finalPoints);

      expect(sumShuffled, closeTo(sumOrdered, 1e-9));
    });

    test('bye recipient gets bye-match-point credit (3 under 3-1-0)', () {
      const config = LeaguePointsConfig(bonusByPlacement: _frPointsBonus);
      final awards = engine.compute(
        finalStandings: _standings(8, byePlacement: 4),
        leagueId: 'L1',
        config: config,
      );

      final byeAward = awards.firstWhere((a) => a.participantId == 'P4');
      final noByeAward = awards.firstWhere((a) => a.participantId == 'P5');

      // Bye row carries an extra full-win match-point credit on top of
      // the placement base (ADR-0024 §2; default `bye` = 3).
      expect(byeAward.basePoints - 3, closeTo(8 - 4 + 1 + 4, 1e-9));
      // Non-bye row at place 5 has no such bonus credit beyond its tier.
      expect(noByeAward.basePoints, closeTo(8 - 5 + 1 + 9, 1e-9));
    });
  });
}
