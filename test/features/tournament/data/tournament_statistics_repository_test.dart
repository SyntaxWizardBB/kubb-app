import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_statistics_repository.dart';

/// System-4 mapping tests for the tournament-statistics value types. The
/// RPCs are exercised end-to-end against the DB via SQL fixtures; here we
/// pin the wire -> Dart decoding of the four payload shapes, which is the
/// part the Flutter layer owns.
void main() {
  group('TournamentSeriesSummary.fromRow', () {
    test('maps the three columns; label falls back to key', () {
      final row = TournamentSeriesSummary.fromRow(const <String, dynamic>{
        'series_key': 'foggy king',
        'series_label': '2. Foggy King',
        'edition_count': 2,
      });
      expect(row.seriesKey, 'foggy king');
      expect(row.seriesLabel, '2. Foggy King');
      expect(row.editionCount, 2);

      final noLabel = TournamentSeriesSummary.fromRow(const <String, dynamic>{
        'series_key': 'havana kubb',
        'edition_count': 1,
      });
      expect(noLabel.seriesLabel, 'havana kubb');
    });
  });

  group('TournamentSeriesStats.fromJson', () {
    test('decodes editions, distribution and the optional participant block',
        () {
      final stats = TournamentSeriesStats.fromJson(const <String, dynamic>{
        'editions': <dynamic>[
          <String, dynamic>{
            'tournament_id': 'fa000000-0000-0000-0000-0000000000a1',
            'display_name': '1. Foggy King',
            'completed_at': '2026-01-01T00:00:00+00:00',
            'field_size': 8,
            'winner_participant_id': 'u-a',
          },
        ],
        'placement_distribution': <dynamic>[
          <String, dynamic>{'placement': 1, 'count': 2},
          <String, dynamic>{'placement': 2, 'count': 2},
        ],
        'participant': <String, dynamic>{
          'placements': <dynamic>[
            <String, dynamic>{
              'tournament_id': 'fa000000-0000-0000-0000-0000000000a1',
              'placement': 1,
            },
            <String, dynamic>{
              'tournament_id': 'fa000000-0000-0000-0000-0000000000a2',
              'placement': 2,
            },
          ],
          'best_placement': 1,
          'avg_placement': 1.5,
          'editions_played': 2,
        },
      });

      expect(stats.editions, hasLength(1));
      expect(stats.editions.single.fieldSize, 8);
      expect(stats.editions.single.completedAt, isNotNull);
      expect(stats.editions.single.winnerParticipantId, 'u-a');

      expect(stats.placementDistribution, hasLength(2));
      expect(stats.placementDistribution.first.placement, 1);
      expect(stats.placementDistribution.first.count, 2);

      final perf = stats.participant;
      expect(perf, isNotNull);
      expect(perf!.bestPlacement, 1);
      expect(perf.avgPlacement, 1.5);
      expect(perf.editionsPlayed, 2);
      expect(perf.placements, hasLength(2));
    });

    test('participant block is null when the RPC omits it', () {
      final stats = TournamentSeriesStats.fromJson(const <String, dynamic>{
        'editions': <dynamic>[],
        'placement_distribution': <dynamic>[],
      });
      expect(stats.participant, isNull);
      expect(stats.editions, isEmpty);
      expect(stats.placementDistribution, isEmpty);
    });
  });

  group('TournamentHeadToHead.fromJson', () {
    test('maps counts and derives draws as total - a - b', () {
      final h2h = TournamentHeadToHead.fromJson(const <String, dynamic>{
        'total_matches': 5,
        'a_wins': 2,
        'b_wins': 2,
        'ko_matches': 2,
        'ko_a_wins': 1,
        'ko_b_wins': 1,
        'a_win_rate': 0.4,
      });
      expect(h2h.totalMatches, 5);
      expect(h2h.aWins, 2);
      expect(h2h.bWins, 2);
      expect(h2h.koMatches, 2);
      expect(h2h.aWinRate, 0.4);
      // 5 - 2 - 2 = 1 unresolved.
      expect(h2h.draws, 1);
    });

    test('draws never goes negative', () {
      final h2h = TournamentHeadToHead.fromJson(const <String, dynamic>{
        'total_matches': 2,
        'a_wins': 1,
        'b_wins': 1,
        'a_win_rate': 0.5,
      });
      expect(h2h.draws, 0);
    });
  });

  group('TournamentStatParticipant.fromRow', () {
    test('maps id, name, team flag and editions; name falls back to id', () {
      final team = TournamentStatParticipant.fromRow(const <String, dynamic>{
        'participant_id': 't-1',
        'display_name': 'Zzz Test Klub',
        'is_team': true,
        'editions': 2,
      });
      expect(team.isTeam, isTrue);
      expect(team.displayName, 'Zzz Test Klub');
      expect(team.editions, 2);

      final unnamed = TournamentStatParticipant.fromRow(const <String, dynamic>{
        'participant_id': 'u-9',
        'is_team': false,
        'editions': 1,
      });
      expect(unnamed.displayName, 'u-9');
      expect(unnamed.isTeam, isFalse);
    });
  });

  group('provider arg value equality', () {
    test('SeriesStatsArgs equality keys on series + participant', () {
      const a = SeriesStatsArgs(seriesKey: 's', participantId: 'p');
      const b = SeriesStatsArgs(seriesKey: 's', participantId: 'p');
      const c = SeriesStatsArgs(seriesKey: 's');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('HeadToHeadArgs is order-sensitive', () {
      const ab = HeadToHeadArgs(a: 'x', b: 'y');
      const ab2 = HeadToHeadArgs(a: 'x', b: 'y');
      const ba = HeadToHeadArgs(a: 'y', b: 'x');
      expect(ab, ab2);
      expect(ab == ba, isFalse);
    });
  });
}
