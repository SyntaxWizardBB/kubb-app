import 'package:flutter/foundation.dart';

/// Date-range buckets supported by the stats screen filter bar.
enum StatsDateRange { all, last7Days, last30Days }

/// Stats filter shared by both tabs. Distance is sniper-only, finisseur
/// ranges are finisseur-only — the inactive ranges sit at their defaults.
@immutable
class StatsFilter {
  const StatsFilter({
    this.distanceMin = 4,
    this.distanceMax = 8,
    this.finFieldMin = 0,
    this.finFieldMax = 10,
    this.finBaseMin = 0,
    this.finBaseMax = 5,
    this.dateRange = StatsDateRange.all,
  });

  /// Lower / upper distance bound in metres for the sniper aggregate. The
  /// defaults span the full range and behave like "all distances".
  final double distanceMin;
  final double distanceMax;

  /// Lower / upper field-kubb count for the finisseur aggregate.
  final int finFieldMin;
  final int finFieldMax;

  /// Lower / upper base-kubb count for the finisseur aggregate.
  final int finBaseMin;
  final int finBaseMax;

  final StatsDateRange dateRange;

  bool get isDistanceFullRange => distanceMin == 4 && distanceMax == 8;
  bool get isFieldFullRange => finFieldMin == 0 && finFieldMax == 10;
  bool get isBaseFullRange => finBaseMin == 0 && finBaseMax == 5;

  StatsFilter copyWith({
    double? distanceMin,
    double? distanceMax,
    int? finFieldMin,
    int? finFieldMax,
    int? finBaseMin,
    int? finBaseMax,
    StatsDateRange? dateRange,
  }) {
    return StatsFilter(
      distanceMin: distanceMin ?? this.distanceMin,
      distanceMax: distanceMax ?? this.distanceMax,
      finFieldMin: finFieldMin ?? this.finFieldMin,
      finFieldMax: finFieldMax ?? this.finFieldMax,
      finBaseMin: finBaseMin ?? this.finBaseMin,
      finBaseMax: finBaseMax ?? this.finBaseMax,
      dateRange: dateRange ?? this.dateRange,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StatsFilter &&
      other.distanceMin == distanceMin &&
      other.distanceMax == distanceMax &&
      other.finFieldMin == finFieldMin &&
      other.finFieldMax == finFieldMax &&
      other.finBaseMin == finBaseMin &&
      other.finBaseMax == finBaseMax &&
      other.dateRange == dateRange;

  @override
  int get hashCode => Object.hash(
        distanceMin,
        distanceMax,
        finFieldMin,
        finFieldMax,
        finBaseMin,
        finBaseMax,
        dateRange,
      );
}
