import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/player/data/player_elo_ratings.dart';

void main() {
  group('PlayerEloRatings.fromRows', () {
    test('parses both disciplines from mixed rows', () {
      final ratings = PlayerEloRatings.fromRows(const <Map<String, dynamic>>[
        {'discipline': 'tournament', 'elo': 1320, 'games': 14},
        {'discipline': 'personal', 'elo': 1180, 'games': 6},
      ]);

      expect(ratings.tournament, isNotNull);
      expect(ratings.tournament!.elo, 1320);
      expect(ratings.tournament!.games, 14);
      expect(ratings.personal, isNotNull);
      expect(ratings.personal!.elo, 1180);
      expect(ratings.personal!.games, 6);
    });

    test('only a tournament row leaves personal null', () {
      final ratings = PlayerEloRatings.fromRows(const <Map<String, dynamic>>[
        {'discipline': 'tournament', 'elo': 1200, 'games': 0},
      ]);

      expect(ratings.tournament, isNotNull);
      expect(ratings.personal, isNull);
    });

    test('only a personal row leaves tournament null', () {
      final ratings = PlayerEloRatings.fromRows(const <Map<String, dynamic>>[
        {'discipline': 'personal', 'elo': 1250, 'games': 3},
      ]);

      expect(ratings.personal, isNotNull);
      expect(ratings.tournament, isNull);
    });

    test('empty list yields both null', () {
      final ratings = PlayerEloRatings.fromRows(const <Map<String, dynamic>>[]);

      expect(ratings.tournament, isNull);
      expect(ratings.personal, isNull);
    });

    test('parses elo/games as num/double and missing fields without crashing',
        () {
      final ratings = PlayerEloRatings.fromRows(const <Map<String, dynamic>>[
        {'discipline': 'tournament', 'elo': 1300.0, 'games': 11.0},
        // Missing elo/games default to 0.
        {'discipline': 'personal'},
      ]);

      expect(ratings.tournament!.elo, 1300);
      expect(ratings.tournament!.games, 11);
      expect(ratings.personal!.elo, 0);
      expect(ratings.personal!.games, 0);
    });

    test('ignores unknown discipline values', () {
      final ratings = PlayerEloRatings.fromRows(const <Map<String, dynamic>>[
        {'discipline': 'overall', 'elo': 9999, 'games': 99},
        {'discipline': null, 'elo': 1, 'games': 1},
        {'discipline': 'tournament', 'elo': 1210, 'games': 2},
      ]);

      expect(ratings.tournament!.elo, 1210);
      expect(ratings.personal, isNull);
    });

    test('duplicate discipline rows: last wins', () {
      final ratings = PlayerEloRatings.fromRows(const <Map<String, dynamic>>[
        {'discipline': 'tournament', 'elo': 1100, 'games': 5},
        {'discipline': 'tournament', 'elo': 1400, 'games': 20},
      ]);

      expect(ratings.tournament!.elo, 1400);
      expect(ratings.tournament!.games, 20);
    });
  });

  group('TournamentElo.provisional', () {
    test('games = 9 is provisional', () {
      expect(const TournamentElo(elo: 1200, games: 9).provisional, isTrue);
    });

    test('games = 10 is not provisional', () {
      expect(const TournamentElo(elo: 1200, games: 10).provisional, isFalse);
    });
  });
}
