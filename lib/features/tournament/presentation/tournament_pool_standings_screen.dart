import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Reads `tournament_pool_standings(p_tournament_id)` via the remote port
/// (Architektur §3.5). The RPC returns per-group `ParticipantStats` already
/// sorted by the tournament's tiebreaker chain.
//
// ignore: specify_nonobvious_property_types
final tournamentPoolStandingsProvider =
    FutureProvider.family<List<PoolGroupStandings>, TournamentId>(
        (ref, id) async {
  return ref.read(tournamentRemoteProvider).getPoolStandings(id);
});

/// 5s polling cadence, mirrors `tournamentBracketPollingProvider` (M2).
//
// ignore: specify_nonobvious_property_types
final tournamentPoolStandingsPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    ref.invalidate(tournamentPoolStandingsProvider(id));
  });
  ref.onDispose(timer.cancel);
});

/// Pool-Phase standings view. Top section is a cross-pool overview limited to
/// the top-`qualifiersPerGroup` rows of every group with highlighting; the
/// bottom section exposes one [ExpansionTile] per group (collapsed by default,
/// R-M3.3-4 mitigation) showing the full standings list with rank, total
/// points, wins, Buchholz and kubb diff.
class TournamentPoolStandingsScreen extends ConsumerWidget {
  const TournamentPoolStandingsScreen({
    required this.tournamentId,
    this.qualifiersPerGroup = 2,
    super.key,
  });

  final String tournamentId;
  final int qualifiersPerGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final id = TournamentId(tournamentId);
    ref.watch(tournamentPoolStandingsPollingProvider(id));
    final async = ref.watch(tournamentPoolStandingsProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        title: const Text('Gruppen-Tabelle'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Fehler: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (groups) => groups.isEmpty
            ? Center(
                child: Text(
                  'Keine Pool-Daten verfügbar.',
                  style: TextStyle(color: tokens.fgMuted),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: KubbTokens.space3,
                ),
                children: [
                  _CrossPoolOverview(
                    groups: groups,
                    qualifiers: qualifiersPerGroup,
                  ),
                  const SizedBox(height: KubbTokens.space4),
                  for (final g in groups)
                    _GroupTile(group: g, qualifiers: qualifiersPerGroup),
                ],
              ),
      ),
    );
  }
}

class _CrossPoolOverview extends StatelessWidget {
  const _CrossPoolOverview({required this.groups, required this.qualifiers});

  final List<PoolGroupStandings> groups;
  final int qualifiers;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Qualifikanten-Übersicht',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tokens.fgMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: KubbTokens.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      g.groupLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: KubbTokens.space2,
                      runSpacing: KubbTokens.space1,
                      children: [
                        for (var i = 0;
                            i < g.stats.length && i < qualifiers;
                            i++)
                          _QualifierChip(rank: i + 1, stats: g.stats[i]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QualifierChip extends StatelessWidget {
  const _QualifierChip({required this.rank, required this.stats});

  final int rank;
  final ParticipantStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space1,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.meadow100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.line),
      ),
      child: Text(
        '$rank. ${_short(stats.participantId)} · ${stats.totalPoints}',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  String _short(String s) => s.length <= 8 ? s : s.substring(0, 8);
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.qualifiers});

  final PoolGroupStandings group;
  final int qualifiers;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space4,
        vertical: KubbTokens.space1,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        // Default kollabiert (Acceptance §3, R-M3.3-4); Tap expandiert.
        tilePadding:
            const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
        title: Text(
          group.groupLabel,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${group.stats.length} Teilnehmer',
          style: TextStyle(color: tokens.fgMuted, fontSize: 12),
        ),
        children: [
          const _StandingsHeader(),
          for (var i = 0; i < group.stats.length; i++)
            _StandingsRow(
              rank: i + 1,
              stats: group.stats[i],
              highlight: i < qualifiers,
            ),
        ],
      ),
    );
  }
}

class _StandingsHeader extends StatelessWidget {
  const _StandingsHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      color: tokens.bgSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      child: Row(
        children: [
          _cell('#', flex: 1, tokens: tokens),
          _cell('Team', flex: 4, tokens: tokens),
          _cell('Pkt', flex: 2, tokens: tokens),
          _cell('Sets', flex: 2, tokens: tokens),
          _cell('Buchh.', flex: 2, tokens: tokens),
        ],
      ),
    );
  }

  Widget _cell(String s, {required int flex, required KubbTokens tokens}) =>
      Expanded(
        flex: flex,
        child: Text(
          s,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: tokens.fgMuted,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.rank,
    required this.stats,
    required this.highlight,
  });

  final int rank;
  final ParticipantStats stats;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final buchholz = stats.opponentIds.fold<int>(
      0,
      (acc, id) => acc + (stats.opponentTotalPointsLookup[id] ?? 0),
    );
    return Container(
      decoration: BoxDecoration(
        color: highlight ? KubbTokens.meadow100 : null,
        border: Border(bottom: BorderSide(color: tokens.line, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space3,
      ),
      child: Row(
        children: [
          _cell('$rank', flex: 1, tokens: tokens, bold: true),
          _cell(_short(stats.participantId), flex: 4, tokens: tokens),
          _cell('${stats.totalPoints}', flex: 2, tokens: tokens),
          _cell('${stats.wins}', flex: 2, tokens: tokens),
          _cell('$buchholz', flex: 2, tokens: tokens),
        ],
      ),
    );
  }

  String _short(String s) => s.length <= 8 ? s : s.substring(0, 8);

  Widget _cell(
    String s, {
    required int flex,
    required KubbTokens tokens,
    bool bold = false,
  }) =>
      Expanded(
        flex: flex,
        child: Text(
          s,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: tokens.fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
}
