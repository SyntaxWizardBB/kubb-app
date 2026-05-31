import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/stats/data/match_stats_filter.dart';

/// Holds the active match-stats filter (opponent + date range). The match tab
/// reads it to filter the aggregate and shows active-filter chips.
class MatchStatsFilterNotifier extends Notifier<MatchStatsFilter> {
  @override
  MatchStatsFilter build() => const MatchStatsFilter();

  void setOpponent(String? userId) =>
      state = userId == null
          ? state.copyWith(clearOpponent: true)
          : state.copyWith(opponentUserId: userId);

  void setRange({DateTime? from, DateTime? to}) =>
      state = state.copyWith(
        dateFrom: from,
        dateTo: to,
        clearFrom: from == null,
        clearTo: to == null,
      );

  void clear() => state = const MatchStatsFilter();
}

final matchStatsFilterProvider =
    NotifierProvider<MatchStatsFilterNotifier, MatchStatsFilter>(
  MatchStatsFilterNotifier.new,
);
