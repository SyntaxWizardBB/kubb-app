import 'package:flutter/foundation.dart';

/// Date-range buckets supported by the stats screen filter bar.
enum StatsDateRange { all, last7Days, last30Days }

/// Read-only filter applied to the stats aggregator. `null` distance means
/// "all distances".
@immutable
class StatsFilter {
  const StatsFilter({this.distanceMeters, this.dateRange = StatsDateRange.all});

  final double? distanceMeters;
  final StatsDateRange dateRange;

  StatsFilter copyWith({
    Object? distanceMeters = _sentinel,
    StatsDateRange? dateRange,
  }) {
    return StatsFilter(
      distanceMeters: identical(distanceMeters, _sentinel)
          ? this.distanceMeters
          : distanceMeters as double?,
      dateRange: dateRange ?? this.dateRange,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StatsFilter &&
      other.distanceMeters == distanceMeters &&
      other.dateRange == dateRange;

  @override
  int get hashCode => Object.hash(distanceMeters, dateRange);

  static const Object _sentinel = Object();
}
