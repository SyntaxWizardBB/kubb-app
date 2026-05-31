import 'package:flutter/foundation.dart';

/// Filter for the match-stats tab: by a dueled opponent and/or a free date
/// range. All fields null/empty means "no filter" (show every finalized match).
@immutable
class MatchStatsFilter {
  const MatchStatsFilter({
    this.opponentUserId,
    this.dateFrom,
    this.dateTo,
  });

  /// When set, keep only matches where this user was an opponent.
  final String? opponentUserId;

  /// Inclusive lower / upper bound on the match `startedAt` (local date).
  final DateTime? dateFrom;
  final DateTime? dateTo;

  bool get isActive =>
      opponentUserId != null || dateFrom != null || dateTo != null;

  MatchStatsFilter copyWith({
    String? opponentUserId,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearOpponent = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return MatchStatsFilter(
      opponentUserId:
          clearOpponent ? null : (opponentUserId ?? this.opponentUserId),
      dateFrom: clearFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearTo ? null : (dateTo ?? this.dateTo),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MatchStatsFilter &&
      other.opponentUserId == opponentUserId &&
      other.dateFrom == dateFrom &&
      other.dateTo == dateTo;

  @override
  int get hashCode => Object.hash(opponentUserId, dateFrom, dateTo);
}
