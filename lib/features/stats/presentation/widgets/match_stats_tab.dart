import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/stats/application/match_stats_provider.dart';
import 'package:kubb_app/features/stats/data/match_stats_aggregate.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Match tab body. Watches the match-stats aggregate and renders a wins /
/// losses / ties block plus the recent finished-match list. Tapping a row
/// opens the finished-match detail screen.
class MatchStatsTab extends ConsumerWidget {
  const MatchStatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final asyncAgg = ref.watch(matchStatsProvider);

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

  final MatchStatsAggregate aggregate;
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
            _MetricBlock(aggregate: aggregate, tokens: tokens, l: l),
            const SizedBox(height: KubbTokens.space5),
            _SectionHead(text: l.statsMatchRecentTitle, tokens: tokens),
            const SizedBox(height: KubbTokens.space2),
            _RecentList(rows: aggregate.recentMatches, tokens: tokens, l: l),
          ],
        ),
      );
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.aggregate,
    required this.tokens,
    required this.l,
  });

  final MatchStatsAggregate aggregate;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
        child: Column(
          children: [
            _MetricRow(
              label: l.statsMatchWins,
              value: '${aggregate.wins}',
              divider: true,
              tokens: tokens,
            ),
            _MetricRow(
              label: l.statsMatchLosses,
              value: '${aggregate.losses}',
              divider: true,
              tokens: tokens,
            ),
            _MetricRow(
              label: l.statsMatchTies,
              value: '${aggregate.ties}',
              divider: true,
              tokens: tokens,
            ),
            _MetricRow(
              label: l.statsMatchWinRate,
              value: '${aggregate.winRatePercent} %',
              divider: false,
              tokens: tokens,
            ),
          ],
        ),
      );
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

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.rows,
    required this.tokens,
    required this.l,
  });

  final List<MatchSummary> rows;
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
            _RecentRow(row: rows[i], fmt: fmt, tokens: tokens, l: l),
            if (i < rows.length - 1)
              Divider(height: 1, color: tokens.line),
          ],
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.row,
    required this.fmt,
    required this.tokens,
    required this.l,
  });

  final MatchSummary row;
  final DateFormat fmt;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final outcome = row.callerOutcome;
    final scoreText = (row.finalScoreA != null && row.finalScoreB != null)
        ? '${row.finalScoreA}:${row.finalScoreB}'
        : '—';
    final when = row.completedAt ?? row.startedAt;
    return InkWell(
      onTap: () => context.go('/match/finished/${row.matchId}'),
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space3,
          vertical: KubbTokens.space3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.statsMatchOpponent(row.opponentTeamSize),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tokens.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _OutcomeChip(outcome: outcome, tokens: tokens, l: l),
                      const SizedBox(width: KubbTokens.space2),
                      Text(
                        fmt.format(when.toLocal()),
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              scoreText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({
    required this.outcome,
    required this.tokens,
    required this.l,
  });

  final String? outcome;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (outcome) {
      'won' => (l.statsMatchOutcomeWon, KubbTokens.meadow600),
      'lost' => (l.statsMatchOutcomeLost, KubbTokens.miss),
      'tie' => (l.statsMatchOutcomeTie, tokens.fgMuted),
      _ => (l.statsMatchOutcomeTie, tokens.fgMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
                l.statsMatchEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.fg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: KubbTokens.space2),
              Text(
                l.statsMatchEmptyBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: tokens.fgMuted),
              ),
            ],
          ),
        ),
      );
}
