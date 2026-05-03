import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class StatsSessionList extends StatelessWidget {
  const StatsSessionList({required this.rows, super.key});

  final List<StatsSessionRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _Row(
              row: rows[i],
              showDivider: i < rows.length - 1,
              tokens: tokens,
              l: l,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.showDivider,
    required this.tokens,
    required this.l,
  });

  final StatsSessionRow row;
  final bool showDivider;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.push('/training/summary/${row.sessionId}'),
        child: Container(
          decoration: BoxDecoration(
            border: showDivider
                ? Border(bottom: BorderSide(color: tokens.line))
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  '${row.distanceMeters.toStringAsFixed(1)} m',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '${row.hitRatePercent} %',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: tokens.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${l.statsRowThrows(row.totalThrows)} · '
                  '${_formatDate(row.completedAt)}',
                  style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

  static String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return '$d.$m.${local.year}';
  }
}
