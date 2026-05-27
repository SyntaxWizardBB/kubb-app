import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/season/application/season_standings_provider.dart';

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// One row of the season-standings table (T12). Lazy-rendered by the
/// parent `ListView.builder` (R-M5.3-1).
class StandingsRow extends StatelessWidget {
  const StandingsRow({required this.rank, required this.row, super.key});

  final int rank;
  final SeasonStandingsRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial = row.displayName.isEmpty
        ? '?'
        : row.displayName.characters.first.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space3, vertical: KubbTokens.space3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line, width: 0.5)),
      ),
      child: Row(children: [
        SizedBox(
            width: 32,
            child: Text('$rank',
                style: _tabular.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg))),
        CircleAvatar(
          radius: 14,
          backgroundColor: KubbTokens.meadow100,
          child: Text(initial,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: KubbTokens.meadow700)),
        ),
        const SizedBox(width: KubbTokens.space3),
        Expanded(
          child: Text(row.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.fg)),
        ),
        SizedBox(
            width: 64,
            child: Text(row.totalPoints.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: _tabular.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg))),
        SizedBox(
            width: 40,
            child: Text('${row.tournamentCount}',
                textAlign: TextAlign.end,
                style: _tabular.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted))),
      ]),
    );
  }
}
