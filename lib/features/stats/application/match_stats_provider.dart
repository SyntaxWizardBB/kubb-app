import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/data/match_repository.dart';
import 'package:kubb_app/features/stats/application/match_stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/match_stats_aggregate.dart';

/// All of the caller's finalized matches, newest first (sorted by the RPC).
/// Shared base so the aggregate and the opponent picker fetch the list once.
final _finalizedMatchesProvider =
    FutureProvider<List<MatchSummary>>((ref) async {
  final repo = ref.watch(matchRepositoryProvider);
  return repo.listForCaller(statusFilter: MatchStatus.finalized);
});

/// Distinct opponents the caller has dueled across finalized matches, sorted
/// by display name. Drives the match-stats opponent filter dropdown.
final matchOpponentsProvider = FutureProvider<List<MatchOpponent>>((ref) async {
  final matches = await ref.watch(_finalizedMatchesProvider.future);
  final byId = <String, MatchOpponent>{};
  for (final m in matches) {
    for (final o in m.opponents) {
      byId[o.userId] = o;
    }
  }
  final list = byId.values.toList()
    ..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return list;
});

/// Aggregate over the caller's finalized matches, after applying the active
/// match-stats filter (by dueled opponent and/or date range).
final matchStatsProvider = FutureProvider<MatchStatsAggregate>((ref) async {
  final matches = await ref.watch(_finalizedMatchesProvider.future);
  final filter = ref.watch(matchStatsFilterProvider);

  // Normalise the date bounds to whole local days so the range is inclusive.
  final from = filter.dateFrom == null
      ? null
      : DateTime(
          filter.dateFrom!.year, filter.dateFrom!.month, filter.dateFrom!.day);
  final to = filter.dateTo == null
      ? null
      : DateTime(filter.dateTo!.year, filter.dateTo!.month, filter.dateTo!.day,
          23, 59, 59, 999);

  final filtered = matches.where((m) {
    if (filter.opponentUserId != null &&
        !m.opponents.any((o) => o.userId == filter.opponentUserId)) {
      return false;
    }
    final started = m.startedAt.toLocal();
    if (from != null && started.isBefore(from)) return false;
    if (to != null && started.isAfter(to)) return false;
    return true;
  }).toList(growable: false);

  return MatchStatsAggregate.from(filtered);
});
