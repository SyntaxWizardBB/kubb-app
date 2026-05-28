import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/stats/application/stats_aggregate_provider.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/features/stats/presentation/widgets/active_filter_tags.dart';
import 'package:kubb_app/features/stats/presentation/widgets/finisseur_stats_tab.dart';
import 'package:kubb_app/features/stats/presentation/widgets/match_stats_tab.dart';
import 'package:kubb_app/features/stats/presentation/widgets/stats_aggregate_block.dart';
import 'package:kubb_app/features/stats/presentation/widgets/stats_filter_modal.dart';
import 'package:kubb_app/features/stats/presentation/widgets/stats_session_list.dart';
import 'package:kubb_app/features/stats/presentation/widgets/stats_trend_chart.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tab.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tab
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isFinisseur = _tab.index == 1;
    final isMatch = _tab.index == 2;
    final showFilter = _tab.index == 0 || _tab.index == 1;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar.slots(
        // Stats can be opened via context.go from home (replace) or context.push
        // from settings/training-sheet — Navigator.canPop is unreliable here, so
        // we wire an explicit leading that always lands back on home.
        leading: IconButton(
          icon: const KubbIcon(LucideIcons.arrowLeft),
          color: tokens.fg,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () =>
              Navigator.of(context).canPop() ? context.pop() : context.go('/'),
        ),
        eyebrow: Text(
          l.statsEyebrow.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
        ),
        title: Text(
          l.statsTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.36,
                color: tokens.fg,
              ),
        ),
        trailing: showFilter
            ? IconButton(
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showFilter)
              IconButton(
                tooltip: l.statsFilterTitle,
                icon: const KubbIcon(LucideIcons.sliders),
                onPressed: () =>
                    StatsFilterModal.show(context, finisseur: isFinisseur),
              ),
            const InboxBellAction(),
          ],
        ),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: tokens.fg,
            unselectedLabelColor: tokens.fgMuted,
            indicatorColor: tokens.primary,
            tabs: [
              Tab(text: l.statsTabSniper),
              Tab(text: l.statsTabFinisseur),
              Tab(text: l.statsTabMatch),
            ],
          ),
          if (!isMatch) ActiveFilterTags(isFinisseur: isFinisseur),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _SniperTab(),
                FinisseurStatsTab(),
                MatchStatsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SniperTab extends ConsumerWidget {
  const _SniperTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final asyncAgg = ref.watch(statsAggregateProvider);
    return asyncAgg.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space6),
          child: Text(e.toString(), textAlign: TextAlign.center),
        ),
      ),
      data: (agg) => _Body(aggregate: agg, tokens: tokens, l: l),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.aggregate, required this.tokens, required this.l});

  final StatsAggregate aggregate;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space2,
          KubbTokens.space4,
          KubbTokens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (aggregate.isEmpty) ...[
              _EmptyState(tokens: tokens, l: l),
            ] else ...[
              StatsTrendChart(points: aggregate.trendPoints),
              const SizedBox(height: KubbTokens.space5),
              StatsAggregateBlock(aggregate: aggregate),
              const SizedBox(height: KubbTokens.space5),
              _BestsBlock(aggregate: aggregate, tokens: tokens, l: l),
              const SizedBox(height: KubbTokens.space5),
              _SectionHead(text: l.statsSessionsTitle, tokens: tokens),
              const SizedBox(height: KubbTokens.space2),
              StatsSessionList(rows: aggregate.sessionRows),
            ],
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens, required this.l});

  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Container(
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
      );
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

class _BestsBlock extends StatelessWidget {
  const _BestsBlock({
    required this.aggregate,
    required this.tokens,
    required this.l,
  });

  final StatsAggregate aggregate;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final dist = aggregate.bestHitRateDistance;
    final bestRate = dist == null
        ? '${aggregate.bestHitRatePercent} %'
        : '${aggregate.bestHitRatePercent} %  ·  ${dist.toStringAsFixed(1)} m';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(text: l.statsBestsTitle, tokens: tokens),
        const SizedBox(height: KubbTokens.space2),
        Container(
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
          child: Column(
            children: [
              _BestRow(label: l.statsBestRate, value: bestRate, tokens: tokens, divider: true),
              _BestRow(
                label: l.statsBestStreak,
                value: '${aggregate.longestHitStreak}',
                tokens: tokens,
                divider: true,
              ),
              _BestRow(
                label: l.statsBestDay,
                value: '${aggregate.mostThrowsInOneDay}',
                tokens: tokens,
                divider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BestRow extends StatelessWidget {
  const _BestRow({
    required this.label,
    required this.value,
    required this.tokens,
    required this.divider,
  });

  final String label;
  final String value;
  final KubbTokens tokens;
  final bool divider;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: divider ? Border(bottom: BorderSide(color: tokens.line)) : null,
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
