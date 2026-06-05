import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_ranking_repository.dart';

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Shared leaderboard column metrics. The header strip and the data rows
/// both consume these so the two stay aligned (no drift if one side
/// changes a width independently).
class RankingColumns {
  const RankingColumns._();

  /// Width of the leading rank-number cell.
  static const double rank = 32;

  /// Diameter of the avatar (CircleAvatar radius 14 -> 28).
  static const double avatar = 28;

  /// Width of the trailing total-points cell.
  static const double points = 64;

  /// Width of the trailing tournament-count cell.
  static const double count = 40;
}

/// One row of the all-time tournament leaderboard (P8-Hub-B2). Mirrors the
/// season `StandingsRow` (rank chip, avatar initial, name, total points,
/// tournament count) so both ranking surfaces stay visually consistent.
/// Lazy-rendered by the parent `ListView.builder`.
class TournamentRankingRowTile extends StatelessWidget {
  const TournamentRankingRowTile({required this.row, super.key});

  final TournamentRankingRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial = row.displayName.isEmpty
        ? '?'
        : row.displayName.characters.first.toUpperCase();
    return Container(
      // >= 48 dp touch/list-row height: 2x space3 padding + ~28 dp avatar.
      constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line, width: 0.5)),
      ),
      child: Row(children: [
        SizedBox(
          width: RankingColumns.rank,
          child: Text(
            '${row.rank}',
            style: _tabular.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
          ),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: KubbTokens.meadow100,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: KubbTokens.meadow700,
            ),
          ),
        ),
        const SizedBox(width: KubbTokens.space3),
        Expanded(
          child: Text(
            row.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.fg,
            ),
          ),
        ),
        SizedBox(
          width: RankingColumns.points,
          child: Text(
            row.totalPoints.toStringAsFixed(1),
            textAlign: TextAlign.end,
            style: _tabular.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
          ),
        ),
        SizedBox(
          width: RankingColumns.count,
          child: Text(
            '${row.tournamentCount}',
            textAlign: TextAlign.end,
            style: _tabular.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.fgMuted,
            ),
          ),
        ),
      ]),
    );
  }
}
