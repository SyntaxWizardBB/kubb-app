import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/tournament/data/tournament_ranking_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_ranking_row.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// All-time tournament leaderboard (P8-Hub-B2, "Rangliste").
///
/// Four tabs — Liga A / Liga B / Liga C / Einzel — each backed by the
/// P8-Hub-B1 RPC `tournament_ranking_get` via [tournamentRankingProvider].
/// Rows follow the season-standings visual (rank, name, total points,
/// tournament count). Reached from the Tournament-Hub; lives on the
/// tournament branch so `context.push` keeps the BottomNav put.
class TournamentRankingScreen extends StatefulWidget {
  const TournamentRankingScreen({super.key});

  @override
  State<TournamentRankingScreen> createState() =>
      _TournamentRankingScreenState();
}

class _TournamentRankingScreenState extends State<TournamentRankingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  /// Tab order maps 1:1 onto the wire buckets A, B, C, EINZEL.
  static const _buckets = <RankingBucket>[
    RankingBucket.ligaA,
    RankingBucket.ligaB,
    RankingBucket.ligaC,
    RankingBucket.einzel,
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _buckets.length, vsync: this);
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
        title: l.tournamentHubRankingTitle,
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: tokens.fg,
            unselectedLabelColor: tokens.fgMuted,
            indicatorColor: tokens.primary,
            tabs: [
              Tab(text: l.tournamentRankingTabLigaA),
              Tab(text: l.tournamentRankingTabLigaB),
              Tab(text: l.tournamentRankingTabLigaC),
              Tab(text: l.tournamentRankingTabEinzel),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                for (final bucket in _buckets)
                  _RankingTab(bucket: bucket),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One leaderboard tab: loading / error / empty / data states for a single
/// [RankingBucket], with pull-to-refresh invalidating its provider entry.
class _RankingTab extends ConsumerWidget {
  const _RankingTab({required this.bucket});

  final RankingBucket bucket;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(tournamentRankingProvider(bucket));
    await ref.read(tournamentRankingProvider(bucket).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final async = ref.watch(tournamentRankingProvider(bucket));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(
            l.tournamentRankingError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KubbTokens.miss),
          ),
        ),
      ),
      data: (rows) => RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: rows.isEmpty
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(KubbTokens.space6),
                  child: Text(
                    l.tournamentRankingEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.fgMuted),
                  ),
                ),
              ])
            : Column(
                children: [
                  _RankingHeader(
                    nameLabel: l.tournamentRankingColName,
                    pointsLabel: l.tournamentRankingColPoints,
                    countLabel: l.tournamentRankingColCount,
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) =>
                          TournamentRankingRowTile(row: rows[i]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Column-header strip above the leaderboard list. Column widths line up
/// with [TournamentRankingRowTile].
class _RankingHeader extends StatelessWidget {
  const _RankingHeader({
    required this.nameLabel,
    required this.pointsLabel,
    required this.countLabel,
  });

  final String nameLabel;
  final String pointsLabel;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: tokens.fgMuted,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line, width: 0.5)),
      ),
      child: Row(children: [
        // Rank chip + avatar + gap (space3) align with the row's leading cells.
        const SizedBox(
          width: RankingColumns.rank + RankingColumns.avatar + KubbTokens.space3,
        ),
        Expanded(child: Text(nameLabel.toUpperCase(), style: style)),
        SizedBox(
          width: RankingColumns.points,
          child: Text(
            pointsLabel.toUpperCase(),
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
        SizedBox(
          width: RankingColumns.count,
          child: Text(
            countLabel.toUpperCase(),
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ]),
    );
  }
}
