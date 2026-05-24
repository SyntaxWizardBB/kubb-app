import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/stats/data/match_stats_aggregate.dart';

MatchSummary _fabricate({
  required String matchId,
  required String? winnerTeamId,
  MatchStatus status = MatchStatus.finalized,
  String myTeamId = 'A',
  DateTime? startedAt,
}) {
  return MatchSummary(
    matchId: matchId,
    format: MatchFormat.bo1,
    scoring: MatchScoring.wins,
    status: status,
    startedAt: startedAt ?? DateTime.utc(2026),
    completedAt: DateTime.utc(2026, 1, 2),
    myTeamId: myTeamId,
    opponentTeamSize: 1,
    myRole: MatchRole.participant,
    winnerTeamId: winnerTeamId,
    finalScoreA: winnerTeamId == 'A' ? 6 : 4,
    finalScoreB: winnerTeamId == 'B' ? 6 : 4,
  );
}

MatchSummary _won(String id) => _fabricate(matchId: id, winnerTeamId: 'A');
MatchSummary _lost(String id) => _fabricate(matchId: id, winnerTeamId: 'B');
MatchSummary _tie(String id) => _fabricate(matchId: id, winnerTeamId: null);

void main() {
  group('MatchStatsAggregate', () {
    test('empty list yields the empty aggregate semantics', () {
      final aggregate = MatchStatsAggregate.from(const <MatchSummary>[]);

      expect(aggregate.totalMatches, 0);
      expect(aggregate.wins, 0);
      expect(aggregate.losses, 0);
      expect(aggregate.ties, 0);
      expect(aggregate.isEmpty, isTrue);
      expect(aggregate.winRatePercent, 0);
      expect(aggregate.recentMatches, isEmpty);
    });

    test('MatchStatsAggregate.empty constant matches the from-empty result',
        () {
      expect(MatchStatsAggregate.empty.totalMatches, 0);
      expect(MatchStatsAggregate.empty.isEmpty, isTrue);
      expect(MatchStatsAggregate.empty.winRatePercent, 0);
      expect(MatchStatsAggregate.empty.recentMatches, isEmpty);
    });

    test('counts wins/losses/ties and computes 60% win rate from 3W/2L/1T',
        () {
      final matches = <MatchSummary>[
        _won('w1'),
        _won('w2'),
        _won('w3'),
        _lost('l1'),
        _lost('l2'),
        _tie('t1'),
      ];

      final aggregate = MatchStatsAggregate.from(matches);

      expect(aggregate.totalMatches, 6);
      expect(aggregate.wins, 3);
      expect(aggregate.losses, 2);
      expect(aggregate.ties, 1);
      expect(aggregate.isEmpty, isFalse);
      // 3 wins of 5 decided matches = 60%.
      expect(aggregate.winRatePercent, 60);
    });

    test('2 wins and 0 losses yields 100% win rate', () {
      final matches = <MatchSummary>[_won('w1'), _won('w2')];

      final aggregate = MatchStatsAggregate.from(matches);

      expect(aggregate.wins, 2);
      expect(aggregate.losses, 0);
      expect(aggregate.winRatePercent, 100);
    });

    test('all ties yields 0% win rate (no decided matches)', () {
      final matches = <MatchSummary>[_tie('t1'), _tie('t2'), _tie('t3')];

      final aggregate = MatchStatsAggregate.from(matches);

      expect(aggregate.totalMatches, 3);
      expect(aggregate.ties, 3);
      expect(aggregate.wins, 0);
      expect(aggregate.losses, 0);
      expect(aggregate.winRatePercent, 0);
    });

    test('recentMatches is capped at 10 and preserves input order', () {
      final matches = List<MatchSummary>.generate(
        20,
        (i) => _fabricate(
          matchId: 'm$i',
          winnerTeamId: i.isEven ? 'A' : 'B',
          startedAt: DateTime.utc(2026, 1, 20 - i),
        ),
      );

      final aggregate = MatchStatsAggregate.from(matches);

      expect(aggregate.totalMatches, 20);
      expect(aggregate.recentMatches.length, 10);
      // Preserves the input ordering — first 10 of the source list.
      for (var i = 0; i < 10; i++) {
        expect(aggregate.recentMatches[i].matchId, 'm$i');
      }
    });
  });
}
