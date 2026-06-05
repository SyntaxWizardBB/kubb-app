import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The four all-time leaderboard buckets exposed by the P8-Hub-B1 RPC
/// `tournament_ranking_get`. Each enum case maps deterministically onto
/// exactly the wire value the SQL `CHECK (p_bucket IN ('A','B','C',
/// 'EINZEL'))` accepts — see migration
/// `20261205000000_tournament_ranking_get.sql`.
enum RankingBucket {
  ligaA('A'),
  ligaB('B'),
  ligaC('C'),
  einzel('EINZEL');

  const RankingBucket(this.wire);

  /// Exact wire value handed to the RPC's `p_bucket` parameter. Never
  /// lower-cased / translated — the server only accepts 'A','B','C',
  /// 'EINZEL' (uppercase).
  final String wire;
}

/// One leaderboard row returned by `tournament_ranking_get`.
///
/// Field mapping (RPC column -> Dart):
///   * participant_id   uuid   -> [participantId]   String
///   * display_name     text   -> [displayName]     String
///   * total_points     numeric-> [totalPoints]     double
///   * tournament_count bigint -> [tournamentCount] int
///   * rank             bigint -> [rank]            int
@immutable
class TournamentRankingRow {
  const TournamentRankingRow({
    required this.participantId,
    required this.displayName,
    required this.totalPoints,
    required this.tournamentCount,
    required this.rank,
  });

  final String participantId;
  final String displayName;
  final double totalPoints;
  final int tournamentCount;
  final int rank;
}

/// Maps one raw RPC row onto a [TournamentRankingRow]. Null-/type-robust
/// analog to the season-standings mapping: `numeric` arrives as a `num`
/// (decode to double), `bigint` as a `num`/`int` (decode to int). A
/// missing `display_name` falls back to the participant id so the UI
/// never renders an empty name cell.
TournamentRankingRow tournamentRankingRowFromRow(Map<String, dynamic> row) {
  final participantId = row['participant_id'] as String? ?? '';
  return TournamentRankingRow(
    participantId: participantId,
    displayName: (row['display_name'] as String?) ?? participantId,
    totalPoints: (row['total_points'] as num?)?.toDouble() ?? 0,
    tournamentCount: (row['tournament_count'] as num?)?.toInt() ?? 0,
    rank: (row['rank'] as num?)?.toInt() ?? 0,
  );
}

/// Signature of the low-level RPC call the repository delegates to.
/// Production wiring forwards to `SupabaseClient.rpc`; tests inject a
/// capturing fake to assert the exact RPC name + `p_bucket` value without
/// a live Supabase backend (analog to the spy pattern used across the
/// tournament data tests).
typedef RankingRpcCaller = Future<List<dynamic>> Function(
  String fn,
  Map<String, dynamic> params,
);

/// Wraps the P8-Hub-B1 read RPC `tournament_ranking_get`. Read-only and
/// public (the RPC is granted to anon + authenticated), so no auth
/// plumbing is needed here.
class TournamentRankingRepository {
  TournamentRankingRepository({required SupabaseClient client})
      : _rpc = ((fn, params) => client.rpc<List<dynamic>>(fn, params: params));

  /// Test seam: build the repository around a captured RPC caller instead
  /// of a live client.
  TournamentRankingRepository.withRpc(RankingRpcCaller rpc) : _rpc = rpc;

  final RankingRpcCaller _rpc;

  /// Exact RPC name from the B1 migration. Exposed as a constant so the
  /// contract test can assert it without re-typing the literal.
  static const String rpcName = 'tournament_ranking_get';

  /// Exact RPC parameter key from the B1 migration.
  static const String bucketParam = 'p_bucket';

  /// Loads the all-time leaderboard for [bucket]. Rows arrive pre-sorted
  /// by the server (total_points DESC, tournament_count DESC,
  /// display_name ASC); the `rank` column carries the 1-based position.
  Future<List<TournamentRankingRow>> getRanking(RankingBucket bucket) async {
    final rows = await _rpc(
      rpcName,
      <String, dynamic>{bucketParam: bucket.wire},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(tournamentRankingRowFromRow)
        .toList(growable: false);
  }
}

final tournamentRankingRepositoryProvider =
    Provider<TournamentRankingRepository>(
  (ref) => TournamentRankingRepository(client: Supabase.instance.client),
);

/// AsyncValue family keyed by [RankingBucket] — one entry per leaderboard
/// tab. The Rangliste screen watches `provider(bucket)` for the active tab
/// and invalidates the matching entry on pull-to-refresh.
//
// ignore: specify_nonobvious_property_types
final tournamentRankingProvider =
    FutureProvider.family<List<TournamentRankingRow>, RankingBucket>(
  (ref, bucket) async {
    return ref.read(tournamentRankingRepositoryProvider).getRanking(bucket);
  },
);
