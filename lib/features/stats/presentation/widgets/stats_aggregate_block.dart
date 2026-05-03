import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class StatsAggregateBlock extends StatelessWidget {
  const StatsAggregateBlock({required this.aggregate, super.key});

  final StatsAggregate aggregate;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(
          label: l.statsHitRateLabel,
          value: '${aggregate.hitRatePercent}',
          unit: '%',
          tokens: tokens,
        ),
        const SizedBox(height: KubbTokens.space3),
        Row(
          children: [
            Expanded(
              child: _MiniHero(
                label: l.statsTotalThrowsLabel,
                value: '${aggregate.totalThrows}',
                tokens: tokens,
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _MiniHero(
                label: l.statsTotalSessionsLabel,
                value: '${aggregate.totalSessions}',
                tokens: tokens,
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _MiniHero(
                label: l.statsLongestStreakLabel,
                value: '${aggregate.longestHitStreak}',
                tokens: tokens,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.label,
    required this.value,
    required this.unit,
    required this.tokens,
  });

  final String label;
  final String value;
  final String unit;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space4,
          vertical: KubbTokens.space4,
        ),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
            ),
            const SizedBox(height: KubbTokens.space2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 56,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    color: tokens.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _MiniHero extends StatelessWidget {
  const _MiniHero({required this.label, required this.value, required this.tokens});

  final String label;
  final String value;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space3,
          vertical: KubbTokens.space3,
        ),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
                color: tokens.fgMuted,
              ),
            ),
            const SizedBox(height: KubbTokens.space1),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}
