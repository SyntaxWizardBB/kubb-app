import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/data/match_repository.dart';
import 'package:kubb_app/features/stats/data/match_stats_aggregate.dart';

/// Aggregate over the caller's finalized multi-player matches. Backed by
/// `match_list_for_caller` with `p_status = 'finalized'`; the RPC already
/// returns rows sorted by `started_at desc`, so the aggregate's
/// `recentMatches` projection preserves that order.
///
/// Consumers invalidate this provider when match state changes upstream
/// (e.g. after `match_propose_result` finalizes a match).
final matchStatsProvider = FutureProvider<MatchStatsAggregate>((ref) async {
  final repo = ref.watch(matchRepositoryProvider);
  final matches =
      await repo.listForCaller(statusFilter: MatchStatus.finalized);
  return MatchStatsAggregate.from(matches);
});
