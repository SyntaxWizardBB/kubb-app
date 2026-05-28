import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Final ranking screen. Reads [tournamentStandingsProvider], which
/// uses the client-side `computeStandings` helper from `kubb_domain`
/// — the server gains a dedicated RPC in M2.
class TournamentStandingsScreen extends ConsumerWidget {
  const TournamentStandingsScreen({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentId(tournamentId);
    final async = ref.watch(tournamentStandingsProvider(id));
    final myId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(
          onPressed: () =>
              context.go(TournamentRoutes.matchesFor(tournamentId)),
        ),
        title: Text(l.tournamentStandingsTitle),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              '${l.tournamentStandingsLoadError}: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (rows) => _Table(rows: rows, callerId: myId),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.callerId});

  final List<ParticipantStats> rows;
  final String? callerId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(
            l.tournamentStandingsEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.fgMuted),
          ),
        ),
      );
    }
    return Column(
      children: [
        _HeaderRow(),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final s = rows[i];
              final isMe = callerId != null && s.participantId == callerId;
              return _DataRow(rank: i + 1, stats: s, highlight: isMe);
            },
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Container(
      color: tokens.bgSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      child: Row(
        children: [
          _cell(l.tournamentStandingsRank, flex: 1, tokens: tokens),
          _cell(l.tournamentStandingsPlayer, flex: 4, tokens: tokens),
          _cell(l.tournamentStandingsTotal, flex: 2, tokens: tokens),
          _cell(l.tournamentStandingsWins, flex: 2, tokens: tokens),
          _cell(l.tournamentStandingsBuchholz, flex: 2, tokens: tokens),
          _cell(l.tournamentStandingsKubbDiff, flex: 2, tokens: tokens),
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

class _DataRow extends StatelessWidget {
  const _DataRow({
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
    final diff = stats.kubbsScored - stats.kubbsConceded;
    final buchholz = stats.opponentIds
        .fold<int>(0, (acc, id) => acc + (stats.opponentTotalPointsLookup[id] ?? 0));
    return Container(
      decoration: BoxDecoration(
        color: highlight ? KubbTokens.meadow100 : null,
        border: Border(
          bottom: BorderSide(color: tokens.line, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space3,
      ),
      child: Row(
        children: [
          _cell('$rank', flex: 1, tokens: tokens, bold: true),
          // TODO(W3-T4-consumer): swap to participant.displayName from the
          // tournament_get RPC (`COALESCE(user_profiles.nickname,
          // teams.display_name)`) so standings stop showing UUID
          // substrings — Wave-B-Polish nachgezogen (R13-F-02).
          _cell(_short(stats.participantId), flex: 4, tokens: tokens),
          _cell('${stats.totalPoints}', flex: 2, tokens: tokens),
          _cell('${stats.wins}', flex: 2, tokens: tokens),
          _cell('$buchholz', flex: 2, tokens: tokens),
          _cell('$diff', flex: 2, tokens: tokens),
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
