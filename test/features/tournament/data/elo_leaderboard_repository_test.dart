import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/elo_leaderboard_repository.dart';

/// Contract tests for the tournament-ELO best-list repository
/// (`docs/ELO_RATINGS.md` §7, RPC `elo_leaderboard_get`, migration
/// `20261222000000`).
///
/// The production [EloLeaderboardRepository] calls
/// `SupabaseClient.rpc('elo_leaderboard_get', params: {'p_limit': ...})`.
/// We exercise the exact contract through the
/// [EloLeaderboardRepository.withRpc] test seam, capturing the RPC name +
/// params and returning canned rows — no live Supabase backend required.
void main() {
  group('EloLeaderboardRepository.getLeaderboard', () {
    test('calls elo_leaderboard_get with the p_limit param', () async {
      String? capturedFn;
      Map<String, dynamic>? capturedParams;
      final repo = EloLeaderboardRepository.withRpc((fn, params) async {
        capturedFn = fn;
        capturedParams = params;
        return const <dynamic>[];
      });

      await repo.getLeaderboard(limit: 50);

      expect(capturedFn, 'elo_leaderboard_get');
      expect(capturedParams, <String, dynamic>{'p_limit': 50});
    });

    test('passes the default limit when none is given', () async {
      Map<String, dynamic>? capturedParams;
      final repo = EloLeaderboardRepository.withRpc((fn, params) async {
        capturedParams = params;
        return const <dynamic>[];
      });

      await repo.getLeaderboard();

      expect(
        capturedParams,
        <String, dynamic>{'p_limit': EloLeaderboardRepository.defaultLimit},
      );
    });

    test('exposes the exact RPC name and param key as constants', () {
      expect(EloLeaderboardRepository.rpcName, 'elo_leaderboard_get');
      expect(EloLeaderboardRepository.limitParam, 'p_limit');
    });

    test('maps all six RPC columns onto the value type with Dart types',
        () async {
      final repo = EloLeaderboardRepository.withRpc((fn, params) async {
        return <dynamic>[
          <String, dynamic>{
            'rank': 1,
            'user_id': 'u-1',
            'nickname': 'Krähe',
            'elo': 1620,
            'games': 24,
            'provisional': false,
          },
        ];
      });

      final rows = await repo.getLeaderboard();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.rank, 1);
      expect(row.userId, 'u-1');
      expect(row.nickname, 'Krähe');
      expect(row.elo, 1620);
      expect(row.games, 24);
      expect(row.provisional, isFalse);
    });

    test('row mapper is null-/type-robust (missing nickname, provisional true)',
        () {
      final row = eloLeaderboardRowFromRow(<String, dynamic>{
        'rank': 4,
        'user_id': 'u-2',
        // numeric can arrive as a plain num from PostgREST
        'elo': 1300,
        'games': 4,
        'provisional': true,
      });

      expect(row.rank, 4);
      expect(row.userId, 'u-2');
      // Missing nickname stays empty; the tile renders a '?' initial.
      expect(row.nickname, '');
      expect(row.elo, 1300);
      expect(row.games, 4);
      expect(row.provisional, isTrue);
    });
  });
}
