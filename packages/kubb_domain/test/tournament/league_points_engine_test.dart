import 'package:kubb_domain/src/tournament/league_points_engine.dart';
import 'package:test/test.dart';

List<FinalStandingRow> _standings(int n, {int? byePlacement}) =>
    List<FinalStandingRow>.generate(
      n,
      (i) => FinalStandingRow(
        participantId: 'P${i + 1}',
        placement: i + 1,
        outcomes: <MatchOutcome>[
          if ((i + 1) == byePlacement)
            MatchOutcome.bye
          else if (i < 2)
            MatchOutcome.win
          else if (i < 4)
            MatchOutcome.draw
          else
            MatchOutcome.loss,
        ],
      ),
    );

const _bonus = <int>[16, 12, 8, 4, 9, 6, 3, 0];

void main() {
  group('LeaguePointsEngine.compute', () {
    const engine = LeaguePointsEngine();

    test('TF=1.0, LF=1.0 → final == base (identity)', () {
      const config = LeaguePointsConfig(placementBonus: _bonus);
      final awards = engine.compute(
        standings: _standings(8),
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
        placementBonus: _bonus,
      );
      final awards = engine.compute(
        standings: _standings(8),
        leagueId: 'L1',
        config: config,
      );

      for (final a in awards) {
        expect(a.finalPoints, closeTo(a.basePoints * 3.0, 0.01));
      }
    });

    test('placement 1 with bonus → basePoints reflects bonus_1', () {
      const config = LeaguePointsConfig(placementBonus: _bonus);
      final awards = engine.compute(
        standings: _standings(8),
        leagueId: 'L1',
        config: config,
      );
      final first = awards.firstWhere((a) => a.placement == 1);
      expect(first.basePoints, closeTo(3 + 16, 1e-9));
    });

    test('permutation-invariance: Σ awards stays equal', () {
      const config = LeaguePointsConfig(placementBonus: _bonus);
      final s = _standings(8);
      final reversed = s.reversed.toList();
      double sum(List<FinalStandingRow> rows) => engine
          .compute(standings: rows, leagueId: 'L1', config: config)
          .fold<double>(0, (acc, a) => acc + a.finalPoints);
      expect(sum(s), closeTo(sum(reversed), 1e-9));
    });

    test('bye recipient gets bye match-points (default 3)', () {
      const config = LeaguePointsConfig();
      final awards = engine.compute(
        standings: _standings(4, byePlacement: 1),
        leagueId: 'L1',
        config: config,
      );
      final byeRow = awards.firstWhere((a) => a.placement == 1);
      expect(byeRow.basePoints, equals(3));
    });
  });
}
