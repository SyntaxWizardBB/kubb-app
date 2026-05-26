import 'package:kubb_domain/src/tournament/tiebreaker.dart';
import 'package:meta/meta.dart';

/// Per-group standings snapshot returned by `tournament_pool_standings`
/// (architecture §3.5). [groupLabel] matches `tournament_matches.group_label`;
/// [stats] is already sorted by the tournament's configured tiebreaker chain.
@immutable
class PoolGroupStandings {
  PoolGroupStandings(this.groupLabel, List<ParticipantStats> stats)
      : stats = List.unmodifiable(stats);

  final String groupLabel;
  final List<ParticipantStats> stats;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PoolGroupStandings) return false;
    if (other.groupLabel != groupLabel) return false;
    if (other.stats.length != stats.length) return false;
    for (var i = 0; i < stats.length; i++) {
      if (other.stats[i] != stats[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(groupLabel, Object.hashAll(stats));
}
