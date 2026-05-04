import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';

/// Holds the active filter for the stats screen. UI mutates via the
/// `setRanges` and `setDateRange` methods; downstream providers rebuild.
class StatsFilterNotifier extends Notifier<StatsFilter> {
  @override
  StatsFilter build() => const StatsFilter();

  void setDateRange(StatsDateRange range) {
    state = state.copyWith(dateRange: range);
  }

  void setDistanceRange(double lo, double hi) {
    state = state.copyWith(distanceMin: lo, distanceMax: hi);
  }

  void setFieldRange(int lo, int hi) {
    state = state.copyWith(finFieldMin: lo, finFieldMax: hi);
  }

  void setBaseRange(int lo, int hi) {
    state = state.copyWith(finBaseMin: lo, finBaseMax: hi);
  }

  // Setter would compete with `state` semantics in Riverpod's Notifier API,
  // so an explicit method reads better at the call site.
  // ignore: use_setters_to_change_properties
  void replace(StatsFilter next) {
    state = next;
  }

  void reset() {
    state = const StatsFilter();
  }
}

final statsFilterProvider =
    NotifierProvider<StatsFilterNotifier, StatsFilter>(StatsFilterNotifier.new);
