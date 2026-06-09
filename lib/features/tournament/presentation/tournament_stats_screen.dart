import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/data/tournament_statistics_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_stats_duel_tab.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Tournament statistics hub (System 4). Two tabs:
///   * **Serien** — every series derived from finalized tournaments
///     (`tournament_series_list`); tap a series for its detail.
///   * **Duell** — head-to-head between any two participants
///     (`tournament_head_to_head`).
///
/// Reached from the Tournament-Hub; lives on the tournament branch so
/// `context.push` keeps the BottomNav put.
class TournamentStatsScreen extends StatefulWidget {
  const TournamentStatsScreen({super.key});

  @override
  State<TournamentStatsScreen> createState() => _TournamentStatsScreenState();
}

class _TournamentStatsScreenState extends State<TournamentStatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentListEyebrow,
        title: l.tournamentHubStatsTitle,
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: tokens.fg,
            unselectedLabelColor: tokens.fgMuted,
            indicatorColor: tokens.primary,
            tabs: [
              Tab(text: l.tournamentStatsTabSeries),
              Tab(text: l.tournamentStatsTabDuel),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _SeriesTab(),
                TournamentStatsDuelTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Serien" tab: loading / error / empty / data for [tournamentSeriesListProvider].
class _SeriesTab extends ConsumerWidget {
  const _SeriesTab();

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(tournamentSeriesListProvider);
    await ref.read(tournamentSeriesListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(tournamentSeriesListProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(
            l.tournamentStatsSeriesError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KubbTokens.miss),
          ),
        ),
      ),
      data: (series) => RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: series.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: KubbEmptyState(
                      title: l.tournamentStatsSeriesEmptyTitle,
                      body: l.tournamentStatsSeriesEmptyBody,
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(KubbTokens.space4),
                itemCount: series.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: KubbTokens.space3),
                itemBuilder: (context, i) => _SeriesTile(
                  series: series[i],
                  editionsLabel: l.tournamentStatsEditionsCount(
                    series[i].editionCount,
                  ),
                  onTap: () => unawaited(
                    context.push(
                      TournamentRoutes.statsSeries,
                      extra: series[i],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// One series card in the list.
class _SeriesTile extends StatelessWidget {
  const _SeriesTile({
    required this.series,
    required this.editionsLabel,
    required this.onTap,
  });

  final TournamentSeriesSummary series;
  final String editionsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Container(
          constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space4,
            vertical: KubbTokens.space3,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(color: tokens.line, width: 0.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.seriesLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      editionsLabel,
                      style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
