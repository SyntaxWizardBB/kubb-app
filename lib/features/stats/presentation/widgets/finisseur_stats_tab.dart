import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/stats/application/stats_aggregate_provider.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/features/stats/presentation/widgets/stats_trend_chart.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Finisseur tab body. Pulls the finisseur aggregate provider and renders
/// success rate, total/average sticks, the special-throw counters and a
/// recent session list. Sniper filters do not apply here.
class FinisseurStatsTab extends ConsumerWidget {
  const FinisseurStatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final asyncAgg = ref.watch(finisseurStatsAggregateProvider);

    return asyncAgg.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space6),
          child: Text(e.toString(), textAlign: TextAlign.center),
        ),
      ),
      data: (agg) => agg.isEmpty
          ? _EmptyState(tokens: tokens, l: l)
          : _Body(aggregate: agg, tokens: tokens, l: l),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.aggregate, required this.tokens, required this.l});

  final FinisseurStatsAggregate aggregate;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space4,
          KubbTokens.space4,
          KubbTokens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatsTrendChart(points: aggregate.successTrendPercent),
            const SizedBox(height: KubbTokens.space5),
            _MetricBlock(aggregate: aggregate, tokens: tokens, l: l),
            const SizedBox(height: KubbTokens.space5),
            _SectionHead(text: l.statsFinisseurSessionsTitle, tokens: tokens),
            const SizedBox(height: KubbTokens.space2),
            _SessionList(rows: aggregate.sessionRows, tokens: tokens, l: l),
          ],
        ),
      );
}

class _MetricBlock extends ConsumerWidget {
  const _MetricBlock({
    required this.aggregate,
    required this.tokens,
    required this.l,
  });

  final FinisseurStatsAggregate aggregate;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    // A disabled tracking toggle drops its metric row entirely so it no longer
    // appears in the stats (mirrors its removal from the aggregate / quota).
    final showLongDubbie = settings?.longDubbieTracking ?? true;
    final showHeli = settings?.heliTracking ?? true;
    final showPenalty = settings?.penaltyKubbTracking ?? true;
    final showKing = settings?.kingThrowTracking ?? true;

    final entries = <(String, String)>[
      (l.statsFinisseurSuccessRate, '${aggregate.successRatePercent} %'),
      (l.statsTotalSessionsLabel, '${aggregate.totalSessions}'),
      (l.statsFinisseurTotalSticks, '${aggregate.totalSticks}'),
      (l.statsFinisseurAvgSticks, aggregate.averageSticks.toStringAsFixed(1)),
      (l.statsFinisseurStickRate, '${aggregate.stickHitRatePercent} %'),
      (l.statsFinisseurMisses, '${aggregate.missSticks}'),
      if (showLongDubbie)
        (
          l.statsFinisseurLongDubbies,
          aggregate.longDubbiesPerSession.toStringAsFixed(2),
        ),
      if (showHeli) (l.statsFinisseurHeli, '${aggregate.heliCount}'),
      if (showPenalty) (l.statsFinisseurPenalty, '${aggregate.penaltyCount}'),
      if (showKing)
        (l.statsFinisseurKingRate, '${aggregate.kingHitRatePercent} %'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            _MetricRow(
              label: entries[i].$1,
              value: entries[i].$2,
              divider: i < entries.length - 1,
              tokens: tokens,
            ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.divider,
    required this.tokens,
  });

  final String label;
  final String value;
  final bool divider;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: tokens.line))
              : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: KubbTokens.space3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: tokens.fgMuted),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

class _SessionList extends StatelessWidget {
  const _SessionList({
    required this.rows,
    required this.tokens,
    required this.l,
  });

  final List<FinisseurSessionRow> rows;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final fmt = DateFormat('dd.MM.yyyy');
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KubbTokens.space3,
                vertical: KubbTokens.space3,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rows[i].success ? tokens.primary : tokens.danger,
                    ),
                  ),
                  const SizedBox(width: KubbTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.statsFinisseurRowConfig(rows[i].field, rows[i].base),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: tokens.fg,
                          ),
                        ),
                        Text(
                          fmt.format(rows[i].completedAt.toLocal()),
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.fgMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    l.statsFinisseurRowSticks(rows[i].sticksUsed),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: tokens.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1) Divider(height: 1, color: tokens.line),
          ],
        ],
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.text, required this.tokens});

  final String text;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.88,
          color: tokens.fgMuted,
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens, required this.l});

  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(KubbTokens.space6),
        child: Container(
          padding: const EdgeInsets.all(KubbTokens.space6),
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
          ),
          child: Column(
            children: [
              Text(
                l.statsEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.fg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: KubbTokens.space2),
              Text(
                l.statsEmptyBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: tokens.fgMuted),
              ),
            ],
          ),
        ),
      );
}
