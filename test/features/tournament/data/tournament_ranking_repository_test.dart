import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_ranking_repository.dart';

/// P8-Hub-B2 contract tests for the all-time ranking repository.
///
/// The production [TournamentRankingRepository] calls
/// `SupabaseClient.rpc('tournament_ranking_get', params: {'p_bucket': ...})`.
/// We exercise the exact contract through the [TournamentRankingRepository.
/// withRpc] test seam, capturing the RPC name + params and returning
/// canned rows — no live Supabase backend required.
void main() {
  group('TournamentRankingRepository.getRanking', () {
    test('calls tournament_ranking_get with the exact p_bucket wire value',
        () async {
      for (final entry in <RankingBucket, String>{
        RankingBucket.ligaA: 'A',
        RankingBucket.ligaB: 'B',
        RankingBucket.ligaC: 'C',
        RankingBucket.einzel: 'EINZEL',
      }.entries) {
        String? capturedFn;
        Map<String, dynamic>? capturedParams;
        final repo = TournamentRankingRepository.withRpc((fn, params) async {
          capturedFn = fn;
          capturedParams = params;
          return const <dynamic>[];
        });

        await repo.getRanking(entry.key);

        expect(capturedFn, 'tournament_ranking_get');
        expect(capturedParams, <String, dynamic>{'p_bucket': entry.value});
      }
    });

    test('exposes the exact RPC name and param key as constants', () {
      expect(TournamentRankingRepository.rpcName, 'tournament_ranking_get');
      expect(TournamentRankingRepository.bucketParam, 'p_bucket');
    });

    test('maps all five RPC columns onto the value type with Dart types',
        () async {
      final repo = TournamentRankingRepository.withRpc((fn, params) async {
        return <dynamic>[
          <String, dynamic>{
            'participant_id': 'p-1',
            'display_name': 'Team Krähe',
            // numeric -> double
            'total_points': 12.5,
            // bigint -> int
            'tournament_count': 3,
            'rank': 1,
          },
        ];
      });

      final rows = await repo.getRanking(RankingBucket.ligaA);

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.participantId, 'p-1');
      expect(row.displayName, 'Team Krähe');
      expect(row.totalPoints, 12.5);
      expect(row.totalPoints, isA<double>());
      expect(row.tournamentCount, 3);
      expect(row.rank, 1);
    });

    test('row mapper is null-/type-robust (integer numeric, missing name)',
        () {
      final row = tournamentRankingRowFromRow(<String, dynamic>{
        'participant_id': 'p-2',
        // numeric can arrive as a plain int from PostgREST
        'total_points': 7,
        'tournament_count': 2,
        'rank': 4,
      });
      // Missing display_name falls back to the participant id.
      expect(row.displayName, 'p-2');
      expect(row.totalPoints, 7.0);
      expect(row.totalPoints, isA<double>());
      expect(row.tournamentCount, 2);
      expect(row.rank, 4);
    });
  });
}
