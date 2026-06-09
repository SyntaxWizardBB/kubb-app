import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_statistics_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Detail of one tournament series (System 4): editions, placement
/// distribution and — when signed in — the caller's own balance, backed by
/// `tournament_series_stats`. The series is handed in via GoRouter `extra`.
class TournamentSeriesDetailScreen extends ConsumerWidget {
  const TournamentSeriesDetailScreen({required this.series, super.key});

  final TournamentSeriesSummary series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final args = SeriesStatsArgs(
      seriesKey: series.seriesKey,
      participantId: myId,
    );
    final async = ref.watch(tournamentSeriesStatsProvider(args));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentStatsSeriesDetailEyebrow,
        title: series.seriesLabel,
      ),
      body: async.when(
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
        data: (stats) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(tournamentSeriesStatsProvider(args));
            await ref.read(tournamentSeriesStatsProvider(args).future);
          },
          child: ListView(
            padding: const EdgeInsets.all(KubbTokens.space4),
            children: [
              if (stats.participant != null)
                _MineSection(perf: stats.participant!),
              _SectionHeader(l.tournamentStatsSectionEditions),
              ...stats.editions.map(
                (e) => _EditionTile(
                  edition: e,
                  fieldLabel: l.tournamentStatsFieldSize(e.fieldSize),
                ),
              ),
              const SizedBox(height: KubbTokens.space5),
              _SectionHeader(l.tournamentStatsSectionPlacements),
              _PlacementChart(buckets: stats.placementDistribution),
              const SizedBox(height: KubbTokens.space6),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(
        top: KubbTokens.space4,
        bottom: KubbTokens.space3,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: tokens.fgMuted,
        ),
      ),
    );
  }
}

/// Own-balance card (best / average placement + participations).
class _MineSection extends StatelessWidget {
  const _MineSection({required this.perf});

  final TournamentParticipantSeriesPerf perf;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    if (perf.editionsPlayed == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(l.tournamentStatsSectionMine),
          Text(
            l.tournamentStatsMineEmpty,
            style: TextStyle(color: tokens.fgMuted),
          ),
        ],
      );
    }
    final best = perf.bestPlacement;
    final avg = perf.avgPlacement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l.tournamentStatsSectionMine),
        Container(
          padding: const EdgeInsets.all(KubbTokens.space4),
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(color: tokens.line, width: 0.5),
          ),
          child: Row(
            children: [
              _MineStat(
                value: best == null
                    ? '–'
                    : l.tournamentStatsPlacementShort(best),
                label: l.tournamentStatsBestPlacement,
              ),
              _MineStat(
                value: avg == null ? '–' : avg.toStringAsFixed(1),
                label: l.tournamentStatsAvgPlacement,
              ),
              _MineStat(
                value: '${perf.editionsPlayed}',
                label: l.tournamentStatsEditionsPlayed,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MineStat extends StatelessWidget {
  const _MineStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: tokens.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: tokens.fgMuted),
          ),
        ],
      ),
    );
  }
}

/// One edition row: name, date, field size, winner mark.
class _EditionTile extends StatelessWidget {
  const _EditionTile({required this.edition, required this.fieldLabel});

  final TournamentSeriesEdition edition;
  final String fieldLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final date = edition.completedAt;
    final dateLabel = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}.'
            '${date.month.toString().padLeft(2, '0')}.${date.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: KubbTokens.space2),
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space4,
        vertical: KubbTokens.space3,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  edition.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel.isEmpty ? fieldLabel : '$dateLabel · $fieldLabel',
                  style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal-bar placement distribution. Bars scale to the largest bucket.
class _PlacementChart extends StatelessWidget {
  const _PlacementChart({required this.buckets});

  final List<TournamentPlacementBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    if (buckets.isEmpty) {
      return Text(
        l.tournamentStatsMineEmpty,
        style: TextStyle(color: tokens.fgMuted),
      );
    }
    final maxCount =
        buckets.map((b) => b.count).fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final b in buckets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    l.tournamentStatsPlacementShort(b.placement),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tokens.fg,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: tokens.bgSunken,
                            borderRadius:
                                BorderRadius.circular(KubbTokens.radiusSm),
                          ),
                        ),
                        Container(
                          height: 18,
                          width: constraints.maxWidth * (b.count / maxCount),
                          decoration: BoxDecoration(
                            color: tokens.primary,
                            borderRadius:
                                BorderRadius.circular(KubbTokens.radiusSm),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: KubbTokens.space3),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${b.count}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tokens.fgMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
