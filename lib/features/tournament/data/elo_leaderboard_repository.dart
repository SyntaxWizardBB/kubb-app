import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One leaderboard row returned by the tournament-ELO best-list RPC
/// `elo_leaderboard_get` (see `docs/ELO_RATINGS.md` §7 + migration
/// `20261222000000`).
///
/// The RPC returns one row per player (never teams), sorted server-side
/// `elo` desc -> `games` desc -> `nickname` asc, and carries a 1-based
/// `rank`. Players with `games < 10` are flagged `provisional` (badge,
/// not hidden).
///
/// Field mapping (RPC column -> Dart):
///   * rank        int     -> [rank]        int
///   * user_id     uuid    -> [userId]      String
///   * nickname    text    -> [nickname]    String
///   * elo         int     -> [elo]         int
///   * games       int     -> [games]       int
///   * provisional boolean -> [provisional] bool
@immutable
class EloLeaderboardRow {
  const EloLeaderboardRow({
    required this.rank,
    required this.userId,
    required this.nickname,
    required this.elo,
    required this.games,
    required this.provisional,
  });

  final int rank;
  final String userId;
  final String nickname;
  final int elo;
  final int games;
  final bool provisional;
}

/// Maps one raw RPC row onto an [EloLeaderboardRow]. Null-/type-robust
/// analog to `tournamentRankingRowFromRow`: int columns arrive as `num`
/// (decode to int), `provisional` as a bool. A missing/empty `nickname`
/// stays empty here; the row tile renders a `'?'` initial fallback.
EloLeaderboardRow eloLeaderboardRowFromRow(Map<String, dynamic> row) {
  return EloLeaderboardRow(
    rank: (row['rank'] as num?)?.toInt() ?? 0,
    userId: row['user_id'] as String? ?? '',
    nickname: row['nickname'] as String? ?? '',
    elo: (row['elo'] as num?)?.toInt() ?? 0,
    games: (row['games'] as num?)?.toInt() ?? 0,
    provisional: row['provisional'] as bool? ?? false,
  );
}

/// Signature of the low-level RPC call the repository delegates to.
/// Production wiring forwards to `SupabaseClient.rpc`; tests inject a
/// capturing fake to assert the exact RPC name + `p_limit` value without
/// a live Supabase backend (analog to the Rangliste's `RankingRpcCaller`).
typedef EloLeaderboardRpcCaller = Future<List<dynamic>> Function(
  String fn,
  Map<String, dynamic> params,
);

/// Wraps the read RPC `elo_leaderboard_get` (`docs/ELO_RATINGS.md` §7,
/// migration `20261222000000`). Read-only and public (the RPC is granted
/// to anon + authenticated), so no auth plumbing is needed here.
class EloLeaderboardRepository {
  EloLeaderboardRepository({required SupabaseClient client})
      : _rpc = ((fn, params) => client.rpc<List<dynamic>>(fn, params: params));

  /// Test seam: build the repository around a captured RPC caller instead
  /// of a live client.
  EloLeaderboardRepository.withRpc(EloLeaderboardRpcCaller rpc) : _rpc = rpc;

  final EloLeaderboardRpcCaller _rpc;

  /// Exact RPC name from the migration. Exposed as a constant so the
  /// contract test can assert it without re-typing the literal.
  static const String rpcName = 'elo_leaderboard_get';

  /// Exact RPC parameter key from the migration.
  static const String limitParam = 'p_limit';

  /// Default number of rows requested from the server. The best-list is a
  /// single global page; 100 covers the visible leaderboard.
  static const int defaultLimit = 100;

  /// Loads the global ELO best-list. Rows arrive pre-sorted by the server
  /// (`elo` DESC, `games` DESC, `nickname` ASC); the `rank` column carries
  /// the 1-based position. No client-side sorting.
  Future<List<EloLeaderboardRow>> getLeaderboard({
    int limit = defaultLimit,
  }) async {
    final rows = await _rpc(
      rpcName,
      <String, dynamic>{limitParam: limit},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(eloLeaderboardRowFromRow)
        .toList(growable: false);
  }
}

final eloLeaderboardRepositoryProvider = Provider<EloLeaderboardRepository>(
  (ref) => EloLeaderboardRepository(client: Supabase.instance.client),
);

/// The global ELO best-list as an [AsyncValue]. One server call with
/// `p_limit` — no `.family` (a single global list, unlike the 4-bucket
/// Rangliste). The screen invalidates this on pull-to-refresh.
final eloLeaderboardProvider = FutureProvider<List<EloLeaderboardRow>>(
  (ref) async => ref.read(eloLeaderboardRepositoryProvider).getLeaderboard(),
);
