import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/features/tournament/data/elo_leaderboard_repository.dart';

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Shared best-list column metrics. The header strip and the data rows both
/// consume these so the two stay aligned (no drift if one side changes a
/// width independently). Mirrors `RankingColumns`.
class EloLeaderboardColumns {
  const EloLeaderboardColumns._();

  /// Width of the leading rank-number cell.
  static const double rank = 32;

  /// Diameter of the avatar (CircleAvatar radius 14 -> 28).
  static const double avatar = 28;

  /// Width of the trailing ELO-value cell.
  static const double elo = 56;

  /// Width of the trailing games-count cell.
  static const double games = 40;
}

/// One row of the global tournament-ELO best-list (`docs/ELO_RATINGS.md`
/// §7). Mirrors `TournamentRankingRowTile` (rank cell, avatar initial,
/// nickname, value, count) so both leaderboard surfaces stay visually
/// consistent. Players with `games < 10` carry a provisional badge — the
/// row is marked, never hidden. Lazy-rendered by the parent
/// `ListView.builder`.
class EloLeaderboardRowTile extends StatelessWidget {
  const EloLeaderboardRowTile({
    required this.row,
    required this.provisionalLabel,
    super.key,
    this.highlight = false,
  });

  final EloLeaderboardRow row;

  /// Localized badge label for provisional players. Passed in so the tile
  /// stays free of `BuildContext`-l10n lookups (parent reads it once).
  final String provisionalLabel;

  /// When true, the row is the current user — highlighted like the
  /// standings `isMe` row.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial =
        row.nickname.isEmpty ? '?' : row.nickname.characters.first.toUpperCase();
    return Container(
      // >= 48 dp touch/list-row height: 2x space3 padding + ~28 dp avatar.
      constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
      decoration: BoxDecoration(
        color: highlight ? KubbTokens.meadow100 : null,
        border: Border(bottom: BorderSide(color: tokens.line, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space3,
      ),
      child: Row(children: [
        SizedBox(
          width: EloLeaderboardColumns.rank,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.fg,
                ),
              ),
              if (row.provisional) ...[
                const SizedBox(height: KubbTokens.space2),
                KubbChip(
                  tone: KubbChipTone.info,
                  label: provisionalLabel,
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          width: EloLeaderboardColumns.elo,
          child: Text(
            '${row.elo}',
            textAlign: TextAlign.end,
            style: _tabular.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
          ),
        ),
        SizedBox(
          width: EloLeaderboardColumns.games,
          child: Text(
            '${row.games}',
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
