import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';

/// Holds the active filter for the stats screen. UI mutates via the
/// `setDistance` and `setDateRange` methods; downstream providers rebuild.
class StatsFilterNotifier extends Notifier<StatsFilter> {
  @override
  StatsFilter build() => const StatsFilter();

  void setDistance(double? distanceMeters) {
    state = state.copyWith(distanceMeters: distanceMeters);
  }

  void setDateRange(StatsDateRange range) {
    state = state.copyWith(dateRange: range);
  }
}

final statsFilterProvider =
    NotifierProvider<StatsFilterNotifier, StatsFilter>(StatsFilterNotifier.new);
